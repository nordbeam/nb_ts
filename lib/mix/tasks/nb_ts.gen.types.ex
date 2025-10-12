defmodule Mix.Tasks.NbTs.Gen.Types do
  @shortdoc "Generates TypeScript types from NbSerializer serializers and Inertia pages"

  @moduledoc """
  Generates TypeScript type definitions from NbSerializer serializers and Inertia page props.

  ## Usage

      mix nb_ts.gen.types

  ## Options

    * `--output-dir` - Output directory for TypeScript files (default: assets/js/types)
    * `--validate` - Validate generated TypeScript files
    * `--verbose` - Show detailed output

  ## Example

      mix nb_ts.gen.types --output-dir assets/types --validate

  This task will:
  1. Discover all NbSerializer serializers in your application
  2. Generate TypeScript interfaces for each serializer
  3. Discover all Inertia page declarations
  4. Generate TypeScript page props interfaces
  5. Create an index.ts file that exports all interfaces
  6. Optionally validate the generated TypeScript
  """

  use Mix.Task

  alias NbTs.Generator

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          output_dir: :string,
          validate: :boolean,
          verbose: :boolean
        ],
        aliases: [
          o: :output_dir,
          v: :validate
        ]
      )

    output_dir = Keyword.get(opts, :output_dir, "assets/js/types")
    validate? = Keyword.get(opts, :validate, false)
    verbose? = Keyword.get(opts, :verbose, false)

    Mix.Task.run("compile")

    # Start nb_ts but not the host application (to avoid starting watchers)
    {:ok, _} = Application.ensure_all_started(:nb_ts)

    # Load the host application modules without starting it
    app = Mix.Project.config()[:app]

    if app do
      Application.load(app)
    end

    Mix.shell().info("Generating TypeScript types...")

    # Call the generator
    case Generator.generate(output_dir: output_dir, validate: validate?, verbose: verbose?) do
      {:ok, results} ->
        Mix.shell().info(
          "✓ Generated #{results.total_files} TypeScript interfaces in #{results.output_dir}"
        )

      {:error, {:validation_failed, file, {:error, reason}}} ->
        relative_file = Path.relative_to(file, output_dir)

        Mix.shell().error("""

        ✗ Validation failed for #{relative_file}:

        #{reason}

        This indicates a bug in NbTs's TypeScript generation.
        Please report at: https://github.com/nordbeam/nb_ts/issues

        You can skip validation with: mix nb_ts.gen.types (without --validate)
        """)

        exit({:shutdown, 1})

      {:error, {:validation_failed, file, reason}} when is_binary(reason) ->
        relative_file = Path.relative_to(file, output_dir)

        Mix.shell().error("""

        ✗ Validation failed for #{relative_file}:

        #{reason}

        This indicates a bug in NbTs's TypeScript generation.
        Please report at: https://github.com/nordbeam/nb_ts/issues

        You can skip validation with: mix nb_ts.gen.types (without --validate)
        """)

        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("✗ Generation failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end
end
