defmodule NbTs.Generator do
  @moduledoc """
  TypeScript type generation and validation.

  Generates TypeScript type definitions from NbSerializer serializers and Inertia page props,
  and validates generated TypeScript code using tsgo (Microsoft's native TypeScript compiler).
  """

  alias NbTs.Interface

  @doc """
  Generates TypeScript types from NbSerializer serializers and Inertia pages.

  ## Options

    * `:output_dir` - Output directory for TypeScript files (default: "assets/js/types")
    * `:validate` - Validate generated TypeScript files (default: false)
    * `:verbose` - Show detailed output (default: false)

  ## Returns

    * `{:ok, results}` - Generation succeeded with results map
    * `{:error, reason}` - Generation failed

  ## Examples

      {:ok, results} = NbTs.Generator.generate(output_dir: "assets/types")
      {:ok, results} = NbTs.Generator.generate(output_dir: "assets/types", validate: true)
  """
  def generate(opts \\ []) do
    output_dir = Keyword.get(opts, :output_dir, "assets/js/types")
    validate? = Keyword.get(opts, :validate, false)
    verbose? = Keyword.get(opts, :verbose, false)

    # Discover serializers
    serializers = discover_serializers()

    if verbose? do
      IO.puts("Found #{length(serializers)} serializers")
    end

    # Discover Inertia pages
    inertia_pages = discover_inertia_pages()

    if verbose? do
      IO.puts("Found #{length(inertia_pages)} Inertia pages")
    end

    # Discover SharedProps modules
    shared_props_modules = discover_shared_props_modules()

    if verbose? do
      IO.puts("Found #{length(shared_props_modules)} SharedProps modules")
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
    validation_result =
      if validate? do
        if verbose? do
          IO.puts("Validating generated TypeScript...")
        end

        case validate_directory(output_dir) do
          :ok ->
            if verbose? do
              IO.puts("✓ All TypeScript files are valid")
            end

            :ok

          {:error, file, reason} ->
            {:error, {:validation_failed, file, reason}}
        end
      else
        :ok
      end

    case validation_result do
      {:error, reason} ->
        {:error, reason}

      :ok ->
        {:ok,
         %{
           serializers: length(serializers),
           shared_props: length(shared_props_modules),
           pages: length(page_files),
           total_files: length(all_files),
           output_dir: output_dir
         }}
    end
  end

  @doc """
  Generates TypeScript types incrementally for specific modules.

  More efficient than `generate/1` when only a few modules changed.

  ## Options

    * `:serializers` - List of serializer modules to regenerate
    * `:controllers` - List of controller modules to regenerate
    * `:shared_props` - List of shared props modules to regenerate
    * `:output_dir` - Output directory (default: "assets/js/types")
    * `:validate` - Validate generated TypeScript (default: false)

  ## Examples

      # Regenerate types for specific modules
      NbTs.Generator.generate_incremental(
        serializers: [MyApp.UserSerializer],
        controllers: [MyAppWeb.UserController],
        output_dir: "assets/types"
      )
  """
  def generate_incremental(opts) do
    serializers = Keyword.get(opts, :serializers, [])
    controllers = Keyword.get(opts, :controllers, [])
    shared_props = Keyword.get(opts, :shared_props, [])
    output_dir = Keyword.get(opts, :output_dir, "assets/js/types")
    validate? = Keyword.get(opts, :validate, false)

    File.mkdir_p!(output_dir)

    # Generate serializer interfaces
    serializer_results =
      Enum.map(serializers, fn serializer ->
        try do
          # Check file existence BEFORE generating
          # Use module name for filename (not interface name)
          module_name =
            serializer
            |> Module.split()
            |> List.last()

          filename = "#{module_name}.ts"
          filepath = Path.join(output_dir, filename)
          status = if File.exists?(filepath), do: :updated, else: :added

          # Now generate
          {interface_name, filename} = generate_interface(serializer, output_dir, false)

          {status, interface_name, filename}
        rescue
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Generate shared props interfaces
    shared_props_results =
      Enum.map(shared_props, fn module ->
        try do
          # Get interface name first
          interface_name =
            module
            |> Module.split()
            |> List.last()
            |> Kernel.<>("Props")

          filename = "#{interface_name}.ts"
          filepath = Path.join(output_dir, filename)
          status = if File.exists?(filepath), do: :updated, else: :added

          # Now generate
          {interface_name, filename} = generate_shared_props_interface(module, output_dir, false)

          {status, interface_name, filename}
        rescue
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Generate page props
    page_results =
      Enum.flat_map(controllers, fn controller ->
        try do
          # Get all pages for this controller
          pages =
            if function_exported?(controller, :__inertia_pages__, 0) do
              controller.__inertia_pages__() |> Enum.map(fn {name, _} -> {name, nil} end)
            else
              []
            end

          # Check existence first, then generate
          page_results_with_status =
            if function_exported?(controller, :__inertia_pages__, 0) do
              controller.__inertia_pages__()
              |> Enum.map(fn {_page_name, page_config} ->
                component_name = page_config.component
                interface_name = component_name_to_page_interface(component_name)
                filename = "#{interface_name}.ts"
                filepath = Path.join(output_dir, filename)
                {interface_name, filename, File.exists?(filepath)}
              end)
            else
              []
            end

          # Now do the actual generation
          page_props = generate_page_props(controller, pages, output_dir, false)

          # Combine with status info
          Enum.zip(page_props, page_results_with_status)
          |> Enum.map(fn {{interface_name, filename}, {_, _, existed?}} ->
            status = if existed?, do: :updated, else: :added
            {status, interface_name, filename}
          end)
        rescue
          _ -> []
        end
      end)

    all_results = serializer_results ++ shared_props_results ++ page_results

    # Check if index needs to be rebuilt
    # If there are many "updated" files but index is small/missing, rebuild instead of incremental update
    index_path = Path.join(output_dir, "index.ts")

    index_entry_count =
      if File.exists?(index_path) do
        index_path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> length()
      else
        0
      end

    # Count actual .ts files (excluding index.ts)
    actual_file_count =
      output_dir
      |> Path.join("*.ts")
      |> Path.wildcard()
      |> Enum.reject(&String.ends_with?(&1, "index.ts"))
      |> length()

    # If index is significantly out of sync (more than 5 files missing), rebuild it
    should_rebuild = actual_file_count > index_entry_count + 5

    # Prepare added and updated lists
    added =
      all_results
      |> Enum.filter(&(elem(&1, 0) == :added))
      |> Enum.map(fn {_, name, file} ->
        # Remove .ts extension for index
        filename_without_ext = String.replace_suffix(file, ".ts", "")
        {name, filename_without_ext}
      end)

    updated =
      all_results
      |> Enum.filter(&(elem(&1, 0) == :updated))
      |> Enum.map(fn {_, name, file} ->
        # Remove .ts extension for index
        filename_without_ext = String.replace_suffix(file, ".ts", "")
        {name, filename_without_ext}
      end)

    if should_rebuild do
      # Index is out of sync - do full rebuild
      NbTs.IndexManager.rebuild_index(output_dir)
    else
      # Index is in sync - do incremental update
      NbTs.IndexManager.update_index(output_dir, added: added, updated: updated)
    end

    # Validate if requested
    if validate? do
      case validate_directory(output_dir) do
        :ok ->
          {:ok,
           %{
             updated_files: length(all_results),
             added: length(added),
             updated: length(updated)
           }}

        {:error, file, reason} ->
          {:error, {:validation_failed, file, reason}}
      end
    else
      {:ok,
       %{
         updated_files: length(all_results),
         added: length(added),
         updated: length(updated)
       }}
    end
  end

  @doc """
  Validates TypeScript code using tsgo (Microsoft's native TypeScript compiler).

  Returns `{:ok, code}` if valid, `{:error, reason}` if invalid.

  Performs full type checking, not just syntax validation.

  ## Examples

      iex> NbTs.Generator.validate("export interface User { id: number; }")
      {:ok, "export interface User { id: number; }"}

      iex> NbTs.Generator.validate("const x: number = 'string'")
      {:error, "Type 'string' is not assignable to type 'number'"}
  """
  def validate(typescript_string) do
    NbTs.TsgoValidator.validate(typescript_string)
  end

  @doc """
  Validates all TypeScript files in a directory.

  Returns `:ok` if all files are valid, `{:error, file, reason}` otherwise.

  Note: Skips validation of index.ts since it only re-exports types from other files
  that are already validated, and tsgo's full type checking would fail on imports
  when validating the file in isolation.

  ## Examples

      iex> NbTs.Generator.validate_directory("assets/types")
      :ok
  """
  def validate_directory(dir) do
    dir
    |> Path.join("*.ts")
    |> Path.wildcard()
    # Skip index.ts - it only re-exports from other files that are already validated
    |> Enum.reject(&String.ends_with?(&1, "index.ts"))
    |> Enum.reduce_while(:ok, fn file, _acc ->
      case validate_file(file) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, file, reason}}
      end
    end)
  end

  @doc """
  Validates a TypeScript file.

  ## Examples

      iex> NbTs.Generator.validate_file("path/to/User.ts")
      {:ok, "export interface User { id: number; }"}
  """
  def validate_file(filepath) do
    filepath
    |> File.read!()
    |> validate()
  end

  # Private: Discovery and generation functions

  defp discover_serializers do
    registered =
      if Process.whereis(NbTs.Registry) do
        NbTs.Registry.all_serializers()
      else
        []
      end

    if registered == [] do
      serializers = find_all_serializers()

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
    app = get_app_name()

    app_modules = get_app_modules(app)
    loaded_modules = :code.all_loaded() |> Enum.map(&elem(&1, 0))

    (app_modules ++ loaded_modules)
    |> Enum.uniq()
    |> Enum.filter(fn module ->
      Code.ensure_loaded?(module) &&
        function_exported?(module, :__nb_serializer_serialize__, 2) &&
        function_exported?(module, :__nb_serializer_type_metadata__, 0)
    end)
  end

  defp discover_shared_props_modules do
    app = get_app_name()

    app_modules = get_app_modules(app)
    loaded_modules = :code.all_loaded() |> Enum.map(&elem(&1, 0))

    (app_modules ++ loaded_modules)
    |> Enum.uniq()
    |> Enum.filter(fn module ->
      Code.ensure_loaded?(module) &&
        function_exported?(module, :__inertia_shared_props__, 0) &&
        function_exported?(module, :build_props, 2)
    end)
  end

  defp discover_inertia_pages do
    app = get_app_name()

    app_modules = get_app_modules(app)
    loaded_modules = :code.all_loaded() |> Enum.map(&elem(&1, 0))

    controllers =
      (app_modules ++ loaded_modules)
      |> Enum.uniq()
      |> Enum.filter(fn module ->
        Code.ensure_loaded?(module) &&
          function_exported?(module, :inertia_page_config, 1)
      end)

    controllers
    |> Enum.map(fn controller ->
      pages = get_controller_pages(controller)
      {controller, pages}
    end)
    |> Enum.reject(fn {_controller, pages} -> pages == [] end)
  end

  defp get_controller_pages(controller) do
    functions = controller.__info__(:functions)

    page_functions =
      Enum.filter(functions, fn {name, arity} ->
        name == :page && arity == 1
      end)

    if page_functions == [] do
      []
    else
      try do
        discover_page_names_from_module(controller)
      rescue
        _ -> []
      end
    end
  end

  defp discover_page_names_from_module(controller) do
    if function_exported?(controller, :__inertia_pages__, 0) do
      controller.__inertia_pages__()
      |> Enum.map(fn {page_name, _config} ->
        config = controller.inertia_page_config(page_name)
        {page_name, config}
      end)
    else
      []
    end
  end

  defp generate_interface(serializer, output_dir, verbose?) do
    interface = Interface.build(serializer)
    typescript = Interface.to_typescript(interface)

    # Use the last part of the module name for the filename (not the interface name)
    module_name =
      serializer
      |> Module.split()
      |> List.last()

    filename = "#{module_name}.ts"
    filepath = Path.join(output_dir, filename)

    File.write!(filepath, typescript)

    if verbose? do
      IO.puts("  Generated #{filename}")
    end

    {interface.name, filename}
  end

  defp generate_shared_props_interface(shared_props_module, output_dir, verbose?) do
    typescript = Interface.generate_shared_props_interface(shared_props_module)

    interface_name =
      shared_props_module
      |> Module.split()
      |> List.last()
      |> Kernel.<>("Props")

    filename = "#{interface_name}.ts"
    filepath = Path.join(output_dir, filename)

    File.write!(filepath, typescript)

    if verbose? do
      IO.puts("  Generated #{filename}")
    end

    {interface_name, filename}
  end

  defp generate_page_props(controller, _pages, output_dir, verbose?) do
    page_results = Interface.generate_page_types(controller, as_list: true)

    Enum.map(page_results, fn {_page_name, page_config, typescript} ->
      component_name = page_config.component
      interface_name = component_name_to_page_interface(component_name)

      filename = "#{interface_name}.ts"
      filepath = Path.join(output_dir, filename)

      File.write!(filepath, typescript)

      if verbose? do
        IO.puts("  Generated #{filename}")
      end

      {interface_name, filename}
    end)
  end

  defp generate_index(interfaces, output_dir) do
    exports =
      interfaces
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map_join("\n", fn {name, filename} ->
        # Strip .ts extension from filename for the import path
        filename_without_ext = String.replace_suffix(filename, ".ts", "")
        ~s(export type { #{name} } from "./#{filename_without_ext}";)
      end)

    index_path = Path.join(output_dir, "index.ts")
    File.write!(index_path, exports <> "\n")
  end

  defp component_name_to_page_interface(component_name) do
    component_name
    |> String.replace("/", "")
    |> String.replace(" ", "")
    |> Kernel.<>("Props")
  end

  defp get_app_name do
    if Code.ensure_loaded?(Mix.Project) do
      Mix.Project.config()[:app]
    end
  end

  defp get_app_modules(app) do
    if app do
      case :application.get_key(app, :modules) do
        {:ok, modules} -> modules
        _ -> []
      end
    else
      []
    end
  end
end
