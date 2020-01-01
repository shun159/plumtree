defmodule Plumtree.Config do
  @moduledoc false

  @default_broadcast_lazy_timer 100
  @default_gossip_wait_timeout 100

  @spec broadcast_lazy_timer() :: pos_integer
  def broadcast_lazy_timer,
    do: get_env(:broadcast_lazy_timer, @default_broadcast_lazy_timer)

  @spec cache_ttl() :: pos_integer
  def cache_ttl,
    do: get_env(:broadcast_lazy_timer, gossip_wait_timeout() + 100)

  @spec gossip_wait_timeout() :: pos_integer
  def gossip_wait_timeout,
    do: get_env(:gossip_wait_timeout, @default_gossip_wait_timeout)

  @spec plumtree_data_root() :: String.t()
  def plumtree_data_root do
    case get_env(:plumtree_data_dir) do
      nil -> nil
      proot -> ensure_path(proot)
    end
  end

  # private functions

  @spec ensure_path(String.t()) :: String.t()
  defp ensure_path(proot) do
    path = Path.join(proot, "peer_service")
    :ok = File.mkdir_p(path)
    path
  end

  defp get_env(item, default \\ nil),
    do: Application.get_env(:plumtree, item, default)
end
