defmodule NbTs.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/assim-fayas/nb_ts"

  def project do
    [
      app: :nb_ts,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url,
      name: "NbTs",
      compilers: Mix.compilers(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {NbTs.Application, []}
    ]
  end

  defp deps do
    [
      # Core dependencies for Rustler NIF
      {:rustler, "~> 0.37", runtime: false},
      {:rustler_precompiled, "~> 0.8"},

      # Optional dependencies
      {:file_system, "~> 1.0", optional: true},
      {:igniter, "~> 0.5", only: [:dev], runtime: false, optional: true},

      # Development dependencies
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    TypeScript type generation and validation for Elixir. Provides the ~TS sigil
    for compile-time TypeScript validation and tools for generating TypeScript
    interfaces from NbSerializer serializers and Inertia page props.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/nb_ts"
      },
      maintainers: ["assim"],
      files: ~w(lib native .formatter.exs mix.exs README.md LICENSE CHANGELOG.md checksum-*.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end

  defp aliases do
    [
      "rustler.download": [
        "rustler_precompiled.download NbTs.Validator"
      ]
    ]
  end
end
