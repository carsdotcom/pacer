defmodule Pacer.MixProject do
  use Mix.Project

  @name "Pacer"
  @version "0.1.0"
  @source_url "https://github.com/carsdotcom/pacer"

  def project do
    [
      app: :pacer,
      contributors: contributors(),
      name: @name,
      version: @version,
      source_url: @source_url,
      build_path: "../../_build",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      description: description(),
      package: package(),
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
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

  def contributors() do
    [
      {"Zack Kayser", "@zkayser"},
      {"Stephanie Lane", "@stelane"}
    ]
  end

  defp description do
    "Dependency graphs for optimal function call ordering"
  end

  defp package do
    [
      name: "pacer",
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.27", only: :dev, runtime: false},
      {:libgraph, "~> 0.16.0"},
      {:nimble_options, ">= 0.0.0"},
      {:telemetry, "~> 0.4"}
    ]
  end
end
