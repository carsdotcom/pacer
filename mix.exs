defmodule Pacer.MixProject do
  use Mix.Project

  @name "Pacer"
  @version "0.1.0"
  @source_url "https://github.com/carsdotcom/pacer"

  def project do
    [
      app: :pacer,
      build_path: "../../_build",
      contributors: contributors(),
      deps: deps(),
      deps_path: "../../deps",
      description: description(),
      docs: docs(),
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      lockfile: "../../mix.lock",
      name: @name,
      source_url: @source_url,
      package: package(),
      version: @version
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

  defp docs do
    [
      main: "Pacer.Workflow",
      logo: __DIR__ <> "/assets/PACER.png",
      extras: ["README.md"]
    ]
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
      {:telemetry, "~> 1.2"}
    ]
  end
end
