defmodule Plumtree.Debug do
  @moduledoc false

  @graphviz_header "digraph {\n  rankdir=LR;\n node [shape = circle];\n"
  @graphviz_footer "\n}"

  @spec print() :: :ok
  def print do
    {:ok, pid} = File.open("plumtree.dot", [:write])

    graph_data = make_dot()
    _ = IO.puts(graph_data)
    _ = IO.write(pid, graph_data)
    _ = File.close(pid)
    :ok
  end

  # private functions

  defp plumtree_graph do
    all_node()
    |> Enum.sort()
    |> Enum.map(&to_edge/1)
    |> Enum.join("\n")
  end

  defp hyparview_graph do
    hv_all_node()
    |> Enum.sort()
    |> Enum.map(&hv_to_edge/1)
    |> Enum.join("\n")
  end

  defp root_def do
    "\"#{Node.self()}\" [style = \"bold\" color = red]\n"
  end

  @spec all_node() :: [Node.t()]
  defp all_node do
    [Node.self() | Node.list()]
  end

  @spec make_dot() :: String.t()
  defp make_dot(),
    do: @graphviz_header <> root_def() <> plumtree_graph() <> "\n" <> hyparview_graph() <> @graphviz_footer

  @spec to_edge(Node.t()) :: String.t()
  defp to_edge(origin) do
    origin
    |> Plumtree.eager_peers()
    |> Enum.reduce([], fn node, acc ->
      ["  \"#{origin}\" -> \"#{node}\" [arrowhead = crow, color = red, style = dotted];" | acc]
    end)
    |> Enum.join("\n")
  end

  @spec hv_all_node() :: [Node.t()]
  defp hv_all_node do
    [Node.self() | Node.list()]
  end

  @spec hv_to_edge(Node.t()) :: String.t()
  defp hv_to_edge(origin) do
    origin
    |> Hyparview.get_active_view()
    |> Enum.reduce([], fn node, acc ->
      ["  \"#{origin}\" -> \"#{node}\" [arrowhead = crow];" | acc]
    end)
    |> Enum.join("\n")
  end
end
