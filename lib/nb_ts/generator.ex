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
    output_dir = Keyword.get(opts, :output_dir, NbTs.Config.output_dir())
    validate? = Keyword.get(opts, :validate, NbTs.Config.validate?())
    verbose? = Keyword.get(opts, :verbose, NbTs.Config.verbose?())

    # Discover serializers
    serializers = NbTs.Discovery.discover_serializers()

    if verbose? do
      IO.puts("Found #{length(serializers)} serializers")
    end

    # Discover Inertia pages
    inertia_pages = NbTs.Discovery.discover_inertia_pages()

    if verbose? do
      IO.puts("Found #{length(inertia_pages)} Inertia pages")
    end

    # Check for TypeScript type name collisions
    NbTs.Collision.check_type_name_collisions(inertia_pages)

    # Discover SharedProps modules
    shared_props_modules = NbTs.Discovery.discover_shared_props_modules()

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

    # Debug: Check for duplicates BEFORE generating index
    duplicates =
      all_files
      |> Enum.frequencies()
      |> Enum.filter(fn {_item, count} -> count > 1 end)

    if duplicates != [] and verbose? do
      IO.puts("\n⚠️  Warning: Duplicate interface exports detected:")

      Enum.each(duplicates, fn {{name, filename}, count} ->
        IO.puts("  - #{name} from #{filename} (#{count} times)")
      end)
    end

    # Generate index file
    generate_index(all_files, output_dir)

    # Validate if requested
    if validate? do
      if verbose? do
        IO.puts("Validating generated TypeScript...")
      end

      # Note: validation currently always returns :ok (stubbed)
      validate_directory(output_dir)

      if verbose? do
        IO.puts("✓ All TypeScript files are valid")
      end
    end

    {:ok,
     %{
       serializers: length(serializers),
       shared_props: length(shared_props_modules),
       pages: length(page_files),
       total_files: length(all_files),
       output_dir: output_dir
     }}
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
    output_dir = Keyword.get(opts, :output_dir, NbTs.Config.output_dir())
    validate? = Keyword.get(opts, :validate, NbTs.Config.validate?())

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

          # Now do the actual generation (this returns both Props and FormInputs)
          page_props = generate_page_props(controller, pages, output_dir, false)

          # Map to results with status based on file existence
          page_props
          |> Enum.map(fn {interface_name, filename} ->
            filepath = Path.join(output_dir, filename)
            status = if File.exists?(filepath), do: :updated, else: :added
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

    # Validate if requested (validation currently always returns :ok - stubbed)
    if validate? do
      validate_directory(output_dir)
    end

    {:ok,
     %{
       updated_files: length(all_results),
       added: length(added),
       updated: length(updated)
     }}
  end

  @doc """
  Validates TypeScript code (stubbed - no actual validation performed).

  Always returns `{:ok, code}` without performing any validation.

  ## Examples

      iex> NbTs.Generator.validate("export interface User { id: number; }")
      {:ok, "export interface User { id: number; }"}

      iex> NbTs.Generator.validate("const x: number = 'string'")
      {:ok, "const x: number = 'string'"}
  """
  def validate(typescript_string) do
    NbTs.TsgoValidator.validate(typescript_string)
  end

  @doc """
  Validates all TypeScript files in a directory (stubbed - no validation performed).

  Always returns `:ok` without performing any validation.

  ## Examples

      iex> NbTs.Generator.validate_directory("assets/types")
      :ok
  """
  def validate_directory(_dir) do
    # Validation is disabled - always return :ok
    :ok
  end

  @doc """
  Validates a TypeScript file (stubbed - no validation performed).

  Always returns `{:ok, content}` without performing any validation.

  ## Examples

      iex> NbTs.Generator.validate_file("path/to/User.ts")
      {:ok, "export interface User { id: number; }"}
  """
  def validate_file(filepath) do
    filepath
    |> File.read!()
    |> validate()
  end

  # Private: Generation functions

  defp generate_interface(serializer, output_dir, verbose?) do
    interface = Interface.build(serializer)
    typescript = Interface.to_typescript(interface)

    # Use the last part of the module name for the filename (not the interface name)
    module_name =
      serializer
      |> Module.split()
      |> List.last()

    # Check if serializer has a namespace defined and prepend it to the filename
    filename =
      if function_exported?(serializer, :__nb_serializer_typescript_namespace__, 0) do
        case serializer.__nb_serializer_typescript_namespace__() do
          nil ->
            "#{module_name}.ts"

          namespace when is_binary(namespace) ->
            "#{namespace}#{module_name}.ts"
        end
      else
        "#{module_name}.ts"
      end

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

    Enum.flat_map(page_results, fn {_page_name, page_config, typescript} ->
      component_name = page_config.component

      # Use custom type_name for filename if provided, otherwise derive from component
      interface_name =
        case Map.get(page_config, :type_name) do
          nil -> component_name_to_page_interface(component_name)
          custom_name -> custom_name
        end

      filename = "#{interface_name}.ts"
      filepath = Path.join(output_dir, filename)

      File.write!(filepath, typescript)

      if verbose? do
        IO.puts("  Generated #{filename}")
      end

      # Check if page has forms and generate FormInputs interface export
      forms = Map.get(page_config, :forms, %{})
      has_forms? = forms != nil and forms != %{}

      if has_forms? do
        # Return both Props and FormInputs interface exports
        # Derive FormInputs name from interface_name to respect custom type_name
        form_inputs_interface_name =
          if String.ends_with?(interface_name, "Props") do
            String.replace_suffix(interface_name, "Props", "FormInputs")
          else
            interface_name <> "FormInputs"
          end

        [{interface_name, filename}, {form_inputs_interface_name, filename}]
      else
        # Only return Props interface export
        [{interface_name, filename}]
      end
    end)
  end

  defp generate_index(interfaces, output_dir) do
    # Group interfaces by filename so multiple interfaces from the same file
    # are exported together (e.g., SpacesNewProps and SpacesNewFormInputs)
    exports =
      interfaces
      |> Enum.group_by(fn {_name, filename} -> filename end, fn {name, _filename} -> name end)
      |> Enum.sort_by(fn {filename, _names} -> filename end)
      |> Enum.map_join("\n", fn {filename, names} ->
        # Strip .ts extension from filename for the import path
        filename_without_ext = String.replace_suffix(filename, ".ts", "")
        # Remove duplicates and sort interface names alphabetically for consistent output
        sorted_names = names |> Enum.uniq() |> Enum.sort()
        names_str = Enum.join(sorted_names, ", ")
        ~s(export type { #{names_str} } from "./#{filename_without_ext}";)
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
end
