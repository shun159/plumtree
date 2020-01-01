defmodule Plumtree.Supervisor do
  @moduledoc false

  @peer_manager %{
    id: Plumtree.PeerServiceManager,
    start: {Plumtree.PeerServiceManager, :start_link, []},
    type: :worker
  }

  @broadcast_manager %{
    id: Plumtree.Broadcast,
    start: {Plumtree.Broadcast, :start_link, []},
    type: :worker
  }

  @children [
    @peer_manager,
    @broadcast_manager
  ]

  @sup_flags [
    strategy: :one_for_all,
    max_restarts: 5,
    max_seconds: 10
  ]

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    Supervisor.init(@children, @sup_flags)
  end
end
