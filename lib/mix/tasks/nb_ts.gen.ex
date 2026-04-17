defmodule Mix.Tasks.NbTs.Gen do
  @shortdoc "Generates TypeScript types from NbSerializer serializers and RPC routers"

  @moduledoc """
  Generates TypeScript type definitions from NbSerializer serializers and RPC routers.

  ## Usage

      mix nb_ts.gen

  ## Options

    * `--output-dir` - Output directory for TypeScript files (default: assets/js/types)
    * `--validate` - Validate generated TypeScript files
    * `--verbose` - Show detailed output

  ## Example

      mix nb_ts.gen --output-dir assets/types --validate

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
      # Load all BEAM files from host app and dependency ebin directories.
      # Dependencies like nb_flop contain serializer modules that need to be
      # loaded into the VM for discovery to find them.
      load_all_beam_files(app)
    end

    Mix.shell().info("Generating TypeScript types...")

    # Call the generator
    # Note: Validation is currently stubbed, so this will always succeed
    {:ok, results} =
      Generator.generate(output_dir: output_dir, validate: validate?, verbose: verbose?)

    Mix.shell().info(
      "✓ Generated #{results.total_files} TypeScript interfaces in #{results.output_dir}"
    )
  end

  # Load all BEAM files from the host app and all dependency ebin directories.
  # This ensures serializer modules from dependencies (e.g., nb_flop) are loaded
  # into the VM so discovery can find them.
  defp load_all_beam_files(app) do
    build_path = Mix.Project.build_path()
    lib_dir = Path.join(build_path, "lib")

    # Load host app first, then all dependencies
    ebin_dirs =
      if File.dir?(lib_dir) do
        host_ebin = Path.join([lib_dir, to_string(app), "ebin"])

        dep_ebins =
          lib_dir
          |> File.ls!()
          |> Enum.reject(&(&1 == to_string(app)))
          |> Enum.map(&Path.join([lib_dir, &1, "ebin"]))
          |> Enum.filter(&File.dir?/1)

        [host_ebin | dep_ebins]
      else
        []
      end

    total_loaded =
      Enum.reduce(ebin_dirs, 0, fn ebin_dir, total ->
        total + load_beam_dir(ebin_dir)
      end)

    if total_loaded > 0 do
      Mix.shell().info("Loaded #{total_loaded} BEAM files from #{lib_dir}")
    end
  end

  defp load_beam_dir(ebin_dir) do
    if File.dir?(ebin_dir) do
      ebin_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".beam"))
      |> Enum.reduce(0, fn beam_file, acc ->
        module_name =
          beam_file
          |> String.replace_suffix(".beam", "")
          |> String.to_atom()

        if :code.is_loaded(module_name) do
          acc
        else
          beam_path = Path.join(ebin_dir, beam_file)

          case :code.load_abs(String.to_charlist(Path.rootname(beam_path))) do
            {:module, _} -> acc + 1
            {:error, _} -> acc
          end
        end
      end)
    else
      0
    end
  end
end
