defmodule Plumtree do
  @moduledoc false

  @spec eager_peers() :: MapSet.t(Node.t()) | none
  def eager_peers,
    do: Plumtree.Broadcast.eager_peers()

  @spec eager_peers(Node.t()) :: MapSet.t(Node.t()) | none
  def eager_peers(root),
    do: GenServer.call({Plumtree.Broadcast, root}, :get_eager_peers)

  @spec lazy_peers() :: MapSet.t(Node.t()) | none
  def lazy_peers,
    do: Plumtree.Broadcast.lazy_peers()
end
