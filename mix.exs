defmodule Plumtree.MixProject do
  use Mix.Project

  def project do
    [
      app: :plumtree,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Plumtree.Application, []}
    ]
  end

  defp deps do
    [
      {:hyparview, github: "shun159/hyparview", branch: "develop"},
      {:riak_dt, github: "basho/riak_dt", branch: "develop-3.0"},
      {:time_compat, github: "lasp-lang/time_compat"},
      # Code Quality
      {:credo, "~> 1.1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0.0-rc.7", only: [:dev], runtime: false},
      # Document
      {:earmark, "~> 1.4.2", only: :doc, runtime: false},
      {:ex_doc, "~> 0.21.1", only: :doc, runtime: false},
      # Test
      {:excoveralls, "~> 0.12", only: :test},
      {:local_cluster, "~> 1.1", only: [:test]}
    ]
  end
end
