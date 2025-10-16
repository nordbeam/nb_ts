defmodule NbTs.Generator do
  @moduledoc """
  TypeScript type generation and validation.

  Generates TypeScript type definitions from NbSerializer serializers and Inertia page props,
  and validates generated TypeScript code using oxc parser (primary) with Elixir fallback.
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

    # Update index incrementally
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

    NbTs.IndexManager.update_index(output_dir, added: added, updated: updated)

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
  Validates TypeScript code.

  Returns `{:ok, code}` if valid, `{:error, reason}` if invalid.

  Uses oxc parser (fast, accurate) when available, otherwise uses
  Elixir pattern matching (slower, less accurate but no dependencies).

  ## Examples

      iex> NbTs.Generator.validate("export interface User { id: number; }")
      {:ok, "export interface User { id: number; }"}

      iex> NbTs.Generator.validate("export interface User { broken")
      {:error, "Unbalanced braces"}
  """
  def validate(typescript_string) do
    case validate_with_oxc(typescript_string) do
      {:ok, _} = result ->
        result

      {:error, :nif_not_loaded} ->
        validate_with_elixir(typescript_string)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Validates all TypeScript files in a directory.

  Returns `:ok` if all files are valid, `{:error, file, reason}` otherwise.

  ## Examples

      iex> NbTs.Generator.validate_directory("assets/types")
      :ok
  """
  def validate_directory(dir) do
    dir
    |> Path.join("*.ts")
    |> Path.wildcard()
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

  # Private: Try oxc validation via NIF
  defp validate_with_oxc(code) do
    if Code.ensure_loaded?(NbTs.Validator) do
      try do
        case NbTs.Validator.validate(code) do
          {:ok, _} = result ->
            result

          # Treat unrecoverable errors as NIF not available (fall back to Elixir)
          {:error, "TypeScript parser encountered an unrecoverable error"} ->
            {:error, :nif_not_loaded}

          {:error, reason} when is_binary(reason) ->
            {:error, reason}

          {:error, _} = error ->
            error
        end
      rescue
        # NIF not loaded error
        ErlangError ->
          {:error, :nif_not_loaded}
      end
    else
      {:error, :nif_not_loaded}
    end
  end

  # Private: Fallback to Elixir pattern matching
  defp validate_with_elixir(str) do
    with :ok <- check_structure(str),
         :ok <- check_syntax(str),
         :ok <- check_types(str) do
      {:ok, str}
    end
  end

  # Legacy API - kept for backward compatibility
  @doc """
  Validates TypeScript interface syntax using Elixir pattern matching.

  This is a legacy function. Use `validate/1` instead for automatic
  oxc/Elixir fallback.
  """
  def validate_interface(typescript_string) do
    with :ok <- check_structure(typescript_string),
         :ok <- check_syntax(typescript_string),
         :ok <- check_types(typescript_string) do
      :ok
    end
  end

  @doc """
  Checks the overall structure of the TypeScript interface.
  """
  def check_structure(str) do
    cond do
      # Allow index files that just export types
      String.contains?(str, "export type {") ->
        :ok

      not String.contains?(str, "export interface") ->
        {:error, "Missing interface declaration"}

      not balanced_braces?(str) ->
        {:error, "Unbalanced braces"}

      not valid_semicolons?(str) ->
        {:error, "Missing or misplaced semicolons"}

      true ->
        :ok
    end
  end

  @doc """
  Checks for common TypeScript syntax errors.
  """
  def check_syntax(str) do
    # Check for common TypeScript syntax errors
    errors = [
      {~r/:\s*;/, "Empty type declaration"},
      {~r/\?\?/, "Double question marks"},
      {~r/:\s*\|/, "Empty union type"},
      {~r/\|\s*\|/, "Empty union member"},
      {~r/Array<\s*>/, "Empty array type"},
      {~r/Record<\s*>/, "Empty record type"},
      {~r/\w+\s+\w+\s*:/, "Missing comma between fields"},
      {~r/\}\}/, "Adjacent braces without separator"}
    ]

    case Enum.find(errors, fn {pattern, _} -> Regex.match?(pattern, str) end) do
      {_, msg} -> {:error, msg}
      nil -> :ok
    end
  end

  @doc """
  Checks the validity of type declarations.
  """
  def check_types(str) do
    # Extract and validate type declarations
    type_pattern = ~r/:\s*([^;]+);/

    types =
      Regex.scan(type_pattern, str, capture: :all_but_first)
      |> Enum.map(&hd/1)
      |> Enum.map(&String.trim/1)

    invalid_type = Enum.find(types, &invalid_type?/1)

    if invalid_type do
      {:error, "Invalid type: #{invalid_type}"}
    else
      :ok
    end
  end

  defp invalid_type?(type) do
    # Check for obviously invalid TypeScript types
    cond do
      # Empty type
      type == "" -> true
      # Unclosed generics
      String.contains?(type, "<") and not String.contains?(type, ">") -> true
      String.contains?(type, ">") and not String.contains?(type, "<") -> true
      # Unclosed brackets
      String.contains?(type, "[") and not String.contains?(type, "]") -> true
      String.contains?(type, "]") and not String.contains?(type, "[") -> true
      # Invalid characters
      Regex.match?(~r/[^a-zA-Z0-9_<>\[\]{}|&\s,.:;"'()]/, type) -> true
      true -> false
    end
  end

  defp balanced_braces?(str) do
    str
    |> String.graphemes()
    |> Enum.reduce({0, 0, 0}, fn
      "{", {braces, brackets, parens} -> {braces + 1, brackets, parens}
      "}", {braces, brackets, parens} -> {braces - 1, brackets, parens}
      "[", {braces, brackets, parens} -> {braces, brackets + 1, parens}
      "]", {braces, brackets, parens} -> {braces, brackets - 1, parens}
      "(", {braces, brackets, parens} -> {braces, brackets, parens + 1}
      ")", {braces, brackets, parens} -> {braces, brackets, parens - 1}
      _, acc -> acc
    end)
    |> case do
      {0, 0, 0} -> true
      _ -> false
    end
  end

  defp valid_semicolons?(str) do
    # Check that field declarations end with semicolons
    lines = String.split(str, "\n")

    field_lines =
      lines
      |> Enum.filter(&String.contains?(&1, ":"))
      |> Enum.reject(&String.contains?(&1, "interface"))
      |> Enum.reject(&String.contains?(&1, "import"))
      |> Enum.reject(&(String.trim(&1) == ""))

    Enum.all?(field_lines, fn line ->
      trimmed = String.trim(line)
      # Skip comments and empty lines
      String.starts_with?(trimmed, "//") or
        String.starts_with?(trimmed, "*") or
        String.ends_with?(trimmed, ";") or
        String.ends_with?(trimmed, "{")
    end)
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

    if page_functions != [] do
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
      |> Enum.map_join("\n", fn {name, _filename} ->
        ~s(export type { #{name} } from "./#{name}";)
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
    else
      nil
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
