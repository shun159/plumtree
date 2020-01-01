defmodule Plumtree.Broadcast do
  @moduledoc false

  use GenServer

  import Logger

  alias __MODULE__, as: State
  alias Plumtree.{Config, PeerServiceManager}

  defstruct lazy_peers: MapSet.new(),
            lazy_queues: Map.new(),
            eager_peers: MapSet.new(),
            all_members: MapSet.new(),
            missing: Map.new(),
            received_messages: Map.new(),
            schedules: Map.new()

  # API functions

  @spec broadcast(any) :: :ok
  def broadcast(message) do
    GenServer.cast(__MODULE__, {:broadcast, message})
  end

  @spec eager_peers() :: MapSet.t(Node.t()) | none
  def eager_peers do
    GenServer.call(__MODULE__, :get_eager_peers)
  end

  @spec lazy_peers() :: MapSet.t(Node.t()) | none
  def lazy_peers do
    GenServer.call(__MODULE__, :get_lazy_peers)
  end

  @spec start_link() :: GenServer.on_start()
  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # GenServer callback functions

  @impl GenServer
  def init(_args) do
    :ok = Hyparview.subscribe()
    schedule_lazy_tick()
    {:ok, %State{}}
  end

  @impl GenServer
  def handle_call(:get_eager_peers, _from, state) do
    {:reply, state.eager_peers, state}
  end

  @impl GenServer
  def handle_call(:get_lazy_peers, _from, state) do
    {:reply, state.lazy_peers, state}
  end

  @impl GenServer
  def handle_cast({:broadcast, msg}, state0) do
    state = broadcast(msg, state0)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(%{type: :gossip} = gossip, state0) do
    :ok = debug("GOSSIP messsage from #{gossip.origin} via #{gossip.sender}")
    state = handle_gossip(gossip, state0)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(%{type: :prune} = prune, state0) do
    :ok = debug("PRUNE messsage from #{prune.sender}")
    state = handle_prune(prune, state0)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(%{type: :graft} = graft, state0) do
    :ok = debug("GRAFT messsage from #{graft.sender}")
    state = handle_graft(graft, state0)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:ihave_announces, ihaves, peer}, state0) do
    :ok = debug("Announcement from #{peer} #{length(ihaves)} messages")
    state = add_to_missing(state0, ihaves)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:ihave_timeout, mid, round, peer}, state0) do
    :ok = debug("mid: #{inspect(mid)} timeout peer: #{peer}")
    :ok = send_message(peer, Plumtree.Message.graft(mid, round))
    {:noreply, add_eager(peer, state0)}
  end

  @impl GenServer
  def handle_cast(:lazy_tick, state0) do
    _tref = schedule_lazy_tick()
    state = send_lazy(state0)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:remove_cache, mid}, state0) do
    :ok = debug("Purge mid: #{inspect(mid)} from cache")
    {:noreply, %{state0 | received_messages: Map.delete(state0.received_messages, mid)}}
  end

  # message handler for message come from the sampling service

  @impl GenServer
  def handle_info({:membership, peer, :up}, state0) do
    state = add_eager(peer, state0)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:membership, peer, :down}, state0) do
    missing = Map.delete(state0.missing, peer)
    eager = MapSet.delete(state0.eager_peers, peer)
    lazy = MapSet.delete(state0.lazy_peers, peer)
    state = %{state0 | missing: missing, eager_peers: eager, lazy_peers: lazy}
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_info, state) do
    {:noreply, state}
  end

  # Private functions

  @spec handle_gossip(Plumtree.Message.gossip_t(), %State{}) :: %State{}
  defp handle_gossip(gossip, state0) do
    state = maybe_cancel_timer(state0, gossip.sender, gossip.mid)
    _ref = schedule_remove_cache_entry(gossip.mid)

    if Map.has_key?(state.received_messages, gossip.mid),
      do: notify_prune(gossip, state),
      else: forward_gossip(gossip, state)
  end

  @spec handle_prune(Plumtree.Message.prune_t(), %State{}) :: %State{}
  defp handle_prune(prune, state0),
    do: add_lazy(prune.sender, state0)

  @spec handle_graft(Plumtree.Message.graft_t(), %State{}) :: %State{}
  defp handle_graft(graft, state0) do
    case Map.get(state0.received_messages, graft.mid) do
      %{type: :gossip} = gossip ->
        :ok = send_message(graft.sender, %{gossip | sender: Node.self()})
        add_eager(graft.sender, state0)

      _ ->
        :ok = error("Unable to GRAFT to #{graft.sender}")
        add_eager(graft.sender, state0)
    end
  end

  @spec broadcast(any, %State{}) :: %State{}
  defp broadcast(message, state0) do
    gossip = Plumtree.Message.gossip(make_ref(), message, Node.self())
    _ref = schedule_remove_cache_entry(gossip.mid)
    :ok = eager_push(gossip, state0)
    state = lazy_push(gossip, state0)
    %{state | received_messages: Map.put(state.received_messages, gossip.mid, gossip)}
  end

  @spec eager_push(Plumtree.Message.gossip_t(), %State{}) :: :ok
  defp eager_push(gossip, state) do
    state.eager_peers
    |> MapSet.delete(Node.self())
    |> MapSet.delete(gossip.sender)
    |> send_message(%{gossip | sender: Node.self()})
  end

  @spec lazy_push(Plumtree.Message.gossip_t(), %State{}) :: %State{}
  defp lazy_push(gossip, state) do
    state.lazy_peers
    |> MapSet.delete(Node.self())
    |> MapSet.delete(gossip.sender)
    |> Enum.reduce(state, fn p, s ->
      ihave = Plumtree.Message.ihave(gossip.mid, gossip.round)
      lazy_queues = Map.update(s.lazy_queues, p, [ihave], &[ihave | &1])
      %{s | lazy_queues: lazy_queues}
    end)
  end

  @spec send_lazy(%State{}) :: %State{}
  defp send_lazy(state) do
    state.lazy_queues
    |> Enum.each(fn {peer, ihaves} ->
      :ok = send_message(peer, {:ihave_announces, ihaves, Node.self()})
    end)

    %{state | lazy_queues: Map.new()}
  end

  @spec add_to_missing(%State{}, [Plumtree.Message.ihave_t()]) :: map
  defp add_to_missing(state, []),
    do: state

  defp add_to_missing(%State{missing: missing0} = state, [ihave | rest]) do
    {missing, schedules} =
      if Map.has_key?(state.received_messages, ihave.mid) do
        {missing0, state.schedules}
      else
        tref =
          if Map.has_key?(state.schedules, ihave.mid),
            do: Map.get(state.schedules, ihave.mid),
            else: schedule_ihave_timer(ihave.mid, ihave.round, ihave.sender)

        {
          Map.update(missing0, ihave.sender, Map.new(), &Map.put(&1, ihave.mid, tref)),
          Map.put(state.schedules, ihave.mid, tref)
        }
      end

    add_to_missing(%{state | missing: missing, schedules: schedules}, rest)
  end

  @spec notify_prune(Plumtree.Message.gossip_t(), %State{}) :: %State{}
  defp notify_prune(gossip, state) do
    :ok = send_message(gossip.sender, Plumtree.Message.prune())
    add_lazy(gossip.sender, state)
  end

  @spec forward_gossip(Plumtree.Message.gossip_t(), %State{}) :: %State{}
  defp forward_gossip(gossip, state) do
    received_messages =
      Map.put(state.received_messages, gossip.mid, %{gossip | sender: Node.self()})

    state1 = %{state | received_messages: received_messages}
    :ok = eager_push(%{gossip | round: gossip.round + 1}, state1)
    state2 = lazy_push(%{gossip | round: gossip.round + 1}, state1)
    add_eager(gossip.sender, state2)
  end

  @spec schedule_lazy_tick() :: reference
  defp schedule_lazy_tick do
    send_after = Config.broadcast_lazy_timer()
    delay_cast(:lazy_tick, send_after)
  end

  @spec schedule_remove_cache_entry(reference) :: reference
  defp schedule_remove_cache_entry(mid) do
    send_after = Config.cache_ttl()
    delay_cast({:remove_cache, mid}, send_after)
  end

  @spec schedule_ihave_timer(reference, non_neg_integer, Node.t()) :: reference
  defp schedule_ihave_timer(mid, round, peer) do
    timeout = Config.gossip_wait_timeout()
    delay_cast({:ihave_timeout, mid, round, peer}, timeout)
  end

  @spec send_message(MapSet.t(Node.t()) | Node.t() | any, Messages.t()) :: :ok
  defp send_message(nodes, msg) when is_map(nodes),
    do: Enum.each(nodes, &send_message(&1, msg))

  defp send_message(node, msg),
    do: GenServer.cast({__MODULE__, node}, msg)

  @spec delay_cast(term, non_neg_integer) :: reference
  defp delay_cast(msg, time),
    do: Process.send_after(__MODULE__, {:"$gen_cast", msg}, time)

  @spec add_eager(Node.t(), %State{}) :: %State{}
  defp add_eager(peer, state) do
    eager_peers = MapSet.put(state.eager_peers, peer)
    lazy_peers = MapSet.delete(state.lazy_peers, peer)
    %{state | eager_peers: eager_peers, lazy_peers: lazy_peers}
  end

  @spec add_lazy(Node.t(), %State{}) :: %State{}
  defp add_lazy(peer, state) do
    eager = MapSet.delete(state.eager_peers, peer)
    lazy = MapSet.put(state.lazy_peers, peer)
    %{state | eager_peers: eager, lazy_peers: lazy}
  end

  @spec maybe_cancel_timer(%State{}, Node.t(), reference) :: %State{}
  defp maybe_cancel_timer(state, peer, mid) do
    case Map.get(state.missing, peer) do
      missings when is_map(missings) ->
        case Map.get(missings, mid) do
          tref when is_reference(tref) ->
            :ok = cancel_timer(tref)
            missing = Map.update!(state.missing, peer, &Map.delete(&1, mid))
            %{state | missing: missing, schedules: Map.delete(state.schedules, mid)}

          _ ->
            state
        end

      _ ->
        state
    end
  end

  @spec cancel_timer(reference | any) :: :ok
  defp cancel_timer(tref) do
    if is_reference(tref), do: Process.cancel_timer(tref)
    :ok
  end
end
