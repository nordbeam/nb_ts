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

  alias NbTs.Interface
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

    # Discover serializers
    serializers = discover_serializers()

    if verbose? do
      Mix.shell().info("Found #{length(serializers)} serializers")
    end

    # Discover Inertia pages
    inertia_pages = discover_inertia_pages()

    if verbose? do
      Mix.shell().info("Found #{length(inertia_pages)} Inertia pages")
    end

    # Discover SharedProps modules
    shared_props_modules = discover_shared_props_modules()

    if verbose? do
      Mix.shell().info("Found #{length(shared_props_modules)} SharedProps modules")
    end

    # Ensure output directory exists
    File.mkdir_p!(output_dir)

    # Generate serializer interfaces
    serializer_files =
      Enum.map(serializers, fn serializer ->
        generate_interface(serializer, output_dir, verbose?)
      end)

    # Generate SharedProps interfaces
    shared_props_files =
      Enum.map(shared_props_modules, fn shared_props_module ->
        generate_shared_props_interface(shared_props_module, output_dir, verbose?)
      end)

    # Generate page props interfaces
    page_files =
      Enum.flat_map(inertia_pages, fn {controller, pages} ->
        generate_page_props(controller, pages, output_dir, verbose?)
      end)

    all_files = serializer_files ++ shared_props_files ++ page_files

    # Generate index file
    generate_index(all_files, output_dir)

    # Validate if requested
    if validate? do
      Mix.shell().info("Validating generated TypeScript...")

      case Generator.validate_directory(output_dir) do
        :ok ->
          Mix.shell().info("✓ All TypeScript files are valid")

        {:error, file, {:error, reason}} ->
          relative_file = Path.relative_to(file, output_dir)

          Mix.shell().error("""

          ✗ Validation failed for #{relative_file}:

          #{reason}

          This indicates a bug in NbTs's TypeScript generation.
          Please report at: https://github.com/assim-fayas/nb_ts/issues

          You can skip validation with: mix nb_ts.gen.types (without --validate)
          """)

          exit({:shutdown, 1})

        {:error, file, reason} when is_binary(reason) ->
          relative_file = Path.relative_to(file, output_dir)

          Mix.shell().error("""

          ✗ Validation failed for #{relative_file}:

          #{reason}

          This indicates a bug in NbTs's TypeScript generation.
          Please report at: https://github.com/assim-fayas/nb_ts/issues

          You can skip validation with: mix nb_ts.gen.types (without --validate)
          """)

          exit({:shutdown, 1})
      end
    end

    Mix.shell().info("✓ Generated #{length(all_files)} TypeScript interfaces in #{output_dir}")
  end

  defp discover_serializers do
    # First try the registry if it's running
    registered =
      if Process.whereis(NbTs.Registry) do
        NbTs.Registry.all_serializers()
      else
        []
      end

    if registered == [] do
      # Fallback: scan all available modules (both loaded and compiled)
      serializers = find_all_serializers()

      # Auto-register discovered serializers
      Enum.each(serializers, fn module ->
        if function_exported?(module, :__nb_serializer_ensure_registered__, 0) do
          module.__nb_serializer_ensure_registered__()
        end
      end)

      serializers
    else
      registered
    end
  end

  defp find_all_serializers do
    # Get the application name
    app = Mix.Project.config()[:app]

    # Get all beam files from the application
    app_modules =
      if app do
        case :application.get_key(app, :modules) do
          {:ok, modules} -> modules
          _ -> []
        end
      else
        []
      end

    # Also check loaded modules
    loaded_modules = :code.all_loaded() |> Enum.map(&elem(&1, 0))

    # Combine and filter for serializers
    (app_modules ++ loaded_modules)
    |> Enum.uniq()
    |> Enum.filter(fn module ->
      Code.ensure_loaded?(module) &&
        function_exported?(module, :__nb_serializer_serialize__, 2) &&
        function_exported?(module, :__nb_serializer_type_metadata__, 0)
    end)
  end

  defp discover_shared_props_modules do
    # Get the application name
    app = Mix.Project.config()[:app]

    # Get all modules
    app_modules =
      if app do
        case :application.get_key(app, :modules) do
          {:ok, modules} -> modules
          _ -> []
        end
      else
        []
      end

    # Also check loaded modules
    loaded_modules = :code.all_loaded() |> Enum.map(&elem(&1, 0))

    # Find all modules that use NbSerializer.Inertia.SharedProps
    (app_modules ++ loaded_modules)
    |> Enum.uniq()
    |> Enum.filter(fn module ->
      Code.ensure_loaded?(module) &&
        function_exported?(module, :__inertia_shared_props__, 0) &&
        function_exported?(module, :build_props, 2)
    end)
  end

  defp generate_interface(serializer, output_dir, verbose?) do
    interface = Interface.build(serializer)
    typescript = Interface.to_typescript(interface)

    filename = "#{interface.name}.ts"
    filepath = Path.join(output_dir, filename)

    File.write!(filepath, typescript)

    if verbose? do
      Mix.shell().info("  Generated #{filename}")
    end

    {interface.name, filename}
  end

  defp generate_shared_props_interface(shared_props_module, output_dir, verbose?) do
    typescript = Interface.generate_shared_props_interface(shared_props_module)

    # Extract interface name from the generated TypeScript
    # The interface name is in the format "ModuleNameProps"
    interface_name =
      shared_props_module
      |> Module.split()
      |> List.last()
      |> Kernel.<>("Props")

    filename = "#{interface_name}.ts"
    filepath = Path.join(output_dir, filename)

    File.write!(filepath, typescript)

    if verbose? do
      Mix.shell().info("  Generated #{filename}")
    end

    {interface_name, filename}
  end

  defp generate_index(interfaces, output_dir) do
    exports =
      interfaces
      |> Enum.map_join("\n", fn {name, _filename} ->
        ~s(export type { #{name} } from "./#{name}";)
      end)

    index_path = Path.join(output_dir, "index.ts")
    File.write!(index_path, exports <> "\n")
  end

  defp discover_inertia_pages do
    # Get the application name
    app = Mix.Project.config()[:app]

    # Get all modules
    app_modules =
      if app do
        case :application.get_key(app, :modules) do
          {:ok, modules} -> modules
          _ -> []
        end
      else
        []
      end

    # Also check loaded modules
    loaded_modules = :code.all_loaded() |> Enum.map(&elem(&1, 0))

    # Find all controllers that use NbSerializer.Inertia.Controller
    controllers =
      (app_modules ++ loaded_modules)
      |> Enum.uniq()
      |> Enum.filter(fn module ->
        Code.ensure_loaded?(module) &&
          function_exported?(module, :inertia_page_config, 1)
      end)

    controllers
    |> Enum.map(fn controller ->
      # Get all inertia pages from this controller
      pages = get_controller_pages(controller)
      {controller, pages}
    end)
    |> Enum.reject(fn {_controller, pages} -> pages == [] end)
  end

  defp get_controller_pages(controller) do
    # Try to get the @inertia_pages attribute via the generated functions
    # We need to discover all pages - we can do this by checking the module's
    # attributes or by introspecting its functions

    # Get all functions from the module
    functions = controller.__info__(:functions)

    # Find all inertia_page_config/1 calls
    # Since page/1 is generated for each declared page, we can use that
    page_functions =
      Enum.filter(functions, fn {name, arity} ->
        name == :page && arity == 1
      end)

    if page_functions != [] do
      # We have pages, so discover them via the __inertia_pages__ function
      try do
        discover_page_names_from_module(controller)
      rescue
        _ -> []
      end
    else
      []
    end
  end

  defp discover_page_names_from_module(controller) do
    # This is a workaround - we'll need to add a function to the controller
    # that returns all page names. Let's check if such a function exists.
    if function_exported?(controller, :__inertia_pages__, 0) do
      controller.__inertia_pages__()
      |> Enum.map(fn {page_name, _config} ->
        config = controller.inertia_page_config(page_name)
        {page_name, config}
      end)
    else
      # Fallback: we need to add this function to the controller
      []
    end
  end

  defp generate_page_props(controller, _pages, output_dir, verbose?) do
    # Use the new Interface.generate_page_types/2 function which properly handles
    # shared modules and generates TypeScript with correct type names
    page_results = Interface.generate_page_types(controller, as_list: true)

    # Write each page interface to its own file
    Enum.map(page_results, fn {_page_name, page_config, typescript} ->
      # Extract interface name from the component name
      # component_name is like "Users/Index" -> interface name is "UsersIndexPageProps"
      component_name = page_config.component
      interface_name = component_name_to_page_interface(component_name)

      filename = "#{interface_name}.ts"
      filepath = Path.join(output_dir, filename)

      File.write!(filepath, typescript)

      if verbose? do
        Mix.shell().info("  Generated #{filename}")
      end

      {interface_name, filename}
    end)
  end

  defp component_name_to_page_interface(component_name) do
    # "Users/Index" -> "UsersIndexProps"
    # "Admin/Dashboard" -> "AdminDashboardProps"
    component_name
    |> String.replace("/", "")
    |> String.replace(" ", "")
    |> Kernel.<>("Props")
  end
end
