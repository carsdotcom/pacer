defmodule Pacer.MixProject do
  use Mix.Project

  def project do
    [
      app: :pacer,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:libgraph, "~> 0.16.0"},
      {:nimble_options, ">= 0.0.0"},
      {:telemetry, "~> 0.4"}
    ]
  end
end
