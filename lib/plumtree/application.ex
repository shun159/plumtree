defmodule Plumtree.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    Plumtree.Supervisor.start_link()
  end
end
