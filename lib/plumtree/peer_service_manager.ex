defmodule Plumtree.PeerServiceManager do
  @moduledoc false

  use GenServer

  import Logger

  alias __MODULE__, as: State

  defstruct [:actor, :membership]

  # API functions

  @spec start_link() :: GenServer.on_start()
  def start_link,
    do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @spec members() :: [Node.t()] | none
  def members,
    do: GenServer.call(__MODULE__, :members)

  @spec get_local_state() :: {:ok, :riak_dt_orswot.orswot()} | none
  def get_local_state,
    do: GenServer.call(__MODULE__, :get_local_state)

  @spec get_actor() :: {:ok, binary} | none
  def get_actor,
    do: GenServer.call(__MODULE__, :get_actor)

  @spec update_state(:riak_dt_orswot.orswot()) :: :ok | none
  def update_state(state),
    do: GenServer.call(__MODULE__, {:update_state, state})

  @spec delete_state() :: :ok | none
  def delete_state,
    do: GenServer.call(__MODULE__, :delete_state)

  # GenServer callback functions

  @impl GenServer
  def init([]) do
    :ok = info("Peer manager started at #{Node.self()}")
    actor = gen_actor()
    membership = maybe_load_state_from_disk(actor)
    {:ok, %State{actor: actor, membership: membership}}
  end

  @impl GenServer
  def handle_call(:members, _from, %State{} = state) do
    {:reply, {:ok, :riak_dt_orswot.value(state.membership)}, state}
  end

  @impl GenServer
  def handle_call(:get_local_state, _from, state) do
    {:reply, {:ok, state.membership}, state}
  end

  @impl GenServer
  def handle_call(:get_actor, _from, state) do
    {:reply, {:ok, state.actor}, state}
  end

  @impl GenServer
  def handle_call({:update_state, new_state}, _from, state) do
    merged_state = :riak_dt_orswot.merge(state.membership, new_state)
    :ok = persist_state(merged_state)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:delete_state, _from, state) do
    :ok = delete_state_from_disk()
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(msg, _from, state) do
    :ok = warn("Unhandled message: #{inspect(msg)}")
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast(msg, state) do
    :ok = warn("Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(msg, state) do
    :ok = warn("Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, _state),
    do: :ok

  @impl GenServer
  def code_change(_oldvsn, state, _extra),
    do: {:ok, state}

  # private functions

  @spec maybe_load_state_from_disk(binary) :: :riak_dt_orswot.orswot()
  defp maybe_load_state_from_disk(actor) do
    case Plumtree.Config.plumtree_data_root() do
      nil ->
        empty_membership(actor)

      dir ->
        dir
        |> filename()
        |> File.exists?()
        |> if(do: load_state_from_disk(dir), else: empty_membership(actor))
    end
  end

  @spec load_state_from_disk(String.t()) :: :riak_dt_orswot.orswot()
  defp load_state_from_disk(dir) do
    {:ok, bin} = File.read(filename(dir))
    {:ok, state} = :riak_dt_orswot.from_binary(bin)
    state
  end

  @spec empty_membership(binary) :: :riak_dt_orswot.orswot()
  defp empty_membership(actor) do
    initial = :riak_dt_orswot.new()
    {:ok, local_state} = :riak_dt_orswot.update({:add, Node.self()}, actor, initial)
    :ok = persist_state(local_state)
    local_state
  end

  @spec persist_state(:riak_dt_orswot.orswot()) :: :ok
  defp persist_state(state),
    do: write_state_to_disk(state)

  @spec write_state_to_disk(:riak_dt_orswot.orswot()) :: :ok
  defp write_state_to_disk(state) do
    case Plumtree.Config.plumtree_data_root() do
      nil -> :ok
      dir -> File.write(filename(dir), :riak_dt_orswot.to_binary(state))
    end
  end

  @spec delete_state_from_disk() :: :ok
  defp delete_state_from_disk do
    case Plumtree.Config.plumtree_data_root() do
      nil -> :ok
      dir -> maybe_remove_dir(dir)
    end
  end

  @spec maybe_remove_dir(String.t()) :: :ok
  defp maybe_remove_dir(dir) do
    case File.rm(filename(dir)) do
      :ok ->
        info("Leaving cluser, removed cluster_state")

      {:error, reason} ->
        info("Unable to remove cluster_state for reason: #{inspect(reason)}")
    end
  end

  @spec gen_actor() :: binary
  defp gen_actor do
    unique = :time_compat.unique_integer([:positive])
    :crypto.hash(:sha, "#{Node.self()}#{unique}")
  end

  @spec filename(String.t()) :: String.t()
  defp filename(dir),
    do: Path.join(dir, "cluster_state")
end
