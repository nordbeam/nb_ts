defmodule NbTs.Interface do
  @moduledoc """
  Builds TypeScript interface from serializer metadata with circular dependency handling.
  """

  defstruct [:name, :fields, :imports, :exports, :is_circular_ref]

  @doc """
  Build interface with proper circular dependency detection.
  """
  def build(serializer_module, opts \\ []) do
    visited = Keyword.get(opts, :visited, MapSet.new())
    interface_name = interface_name(serializer_module)

    # Ensure the module is registered
    if function_exported?(serializer_module, :__nb_serializer_ensure_registered__, 0) do
      serializer_module.__nb_serializer_ensure_registered__()
    end

    if MapSet.member?(visited, serializer_module) do
      # Circular reference detected
      %__MODULE__{
        name: interface_name,
        fields: [],
        imports: [],
        exports: false,
        is_circular_ref: true
      }
    else
      visited = MapSet.put(visited, serializer_module)
      type_metadata = serializer_module.__nb_serializer_type_metadata__()

      # Build fields and collect imports
      {fields, imports} = build_fields_with_imports(type_metadata, visited)

      %__MODULE__{
        name: interface_name,
        fields: fields,
        imports: imports,
        exports: true,
        is_circular_ref: false
      }
    end
  end

  def to_typescript(%__MODULE__{is_circular_ref: true} = interface) do
    # For circular refs, just return the type name
    interface.name
  end

  def to_typescript(%__MODULE__{} = interface) do
    imports = render_imports(interface.imports)
    fields = render_fields(interface.fields)

    typescript = """
    #{imports}#{if imports != "", do: "\n"}export interface #{interface.name} {
    #{fields}
    }
    """

    typescript
  end

  defp interface_name(module) when is_atom(module) do
    # Check if module has a custom TypeScript name
    if function_exported?(module, :__nb_serializer_typescript_name__, 0) do
      case module.__nb_serializer_typescript_name__() do
        nil ->
          # No custom name, use default
          default_interface_name(module)

        custom_name when is_binary(custom_name) ->
          custom_name
      end
    else
      # Module doesn't export the function, use default
      default_interface_name(module)
    end
  end

  defp default_interface_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> String.replace(~r/Serializer$/, "")
  end

  defp build_fields_with_imports(type_metadata, visited) do
    # Handle both map format and list format (for test serializers)
    normalized_metadata =
      case type_metadata do
        %{fields: field_list} when is_list(field_list) ->
          # Convert list format to map format
          Enum.map(field_list, fn field_spec ->
            name = Map.get(field_spec, :name)
            type = Map.get(field_spec, :type)
            opts = Map.get(field_spec, :opts, [])

            # Build type_info map from field spec
            type_info = %{
              type: type,
              optional: Keyword.get(opts, :optional, false),
              nullable: Keyword.get(opts, :nullable, false),
              list: Keyword.get(opts, :list, false),
              serializer: Map.get(field_spec, :serializer)
            }

            {name, type_info}
          end)

        metadata when is_map(metadata) ->
          # Already in map format
          Enum.to_list(metadata)
      end

    {fields, imports} =
      Enum.reduce(normalized_metadata, {[], []}, fn {field_name, type_info},
                                                    {fields_acc, imports_acc} ->
        {field_type, new_imports} = resolve_field_type(type_info, visited)

        field = %{
          name: field_name,
          type: field_type,
          optional: Map.get(type_info, :optional, false),
          nullable: Map.get(type_info, :nullable, false),
          comment: Map.get(type_info, :comment)
        }

        {[field | fields_acc], imports_acc ++ new_imports}
      end)

    {Enum.reverse(fields), Enum.uniq(imports)}
  end

  defp resolve_field_type(type_info, _visited) do
    cond do
      # Handle relationship types
      serializer = type_info[:serializer] ->
        name = interface_name(serializer)
        # Always use type name and add import, regardless of circular status
        {apply_modifiers(name, type_info), [name]}

      # Handle polymorphic types
      type_info[:polymorphic] ->
        type_union = type_info[:polymorphic] |> Enum.map_join(" | ", &to_string/1)
        {type_union, []}

      # Regular types
      true ->
        base_type = NbTs.TypeMapper.to_typescript(type_info)
        {apply_modifiers(base_type, type_info), []}
    end
  end

  defp apply_modifiers(base_type, type_info) do
    type = if type_info[:list], do: "Array<#{base_type}>", else: base_type
    if type_info[:nullable], do: "#{type} | null", else: type
  end

  defp render_imports([]), do: ""

  defp render_imports(imports) do
    imports
    |> Enum.map_join("\n", fn import_name ->
      ~s(import type { #{import_name} } from "./#{import_name}";)
    end)
  end

  defp render_fields(fields) do
    fields
    |> Enum.map_join("\n", &render_field/1)
  end

  defp render_field(field) do
    optional = if field.optional, do: "?", else: ""
    type = field.type

    # Camelize field name for JavaScript/TypeScript conventions
    camelized_name = camelize_atom(field.name)

    "  #{camelized_name}#{optional}: #{type};"
  end

  defp camelize_atom(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> camelize_string()
  end

  defp camelize_string(string) do
    string
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map_join(fn
      # First word stays lowercase
      {word, 0} -> word
      # Rest are capitalized
      {word, _} -> String.capitalize(word)
    end)
  end

  @doc """
  Generate TypeScript interface for a SharedProps module.

  Takes a module that uses NbSerializer.Inertia.SharedProps and generates a
  TypeScript interface with all declared props.

  ## Example

      typescript = NbTs.Interface.generate_shared_props_interface(MyAppWeb.InertiaShared.Shopify)
      # Returns:
      # interface ShopifyProps {
      #   locale: string
      #   apiKey: string
      # }
  """
  def generate_shared_props_interface(shared_props_module) do
    # Get prop declarations from the module
    props = shared_props_module.__inertia_shared_props__()

    # Build the interface name (ModuleName -> ModuleNameProps)
    interface_name = shared_props_interface_name(shared_props_module)

    # Convert props to TypeScript fields
    {fields, imports} = build_shared_props_fields(props)

    # Render imports
    import_statements = render_imports(imports)

    # Render fields
    field_lines = Enum.map_join(fields, "\n", &render_field/1)

    typescript = """
    #{import_statements}#{if import_statements != "", do: "\n"}export interface #{interface_name} {
    #{field_lines}
    }
    """

    typescript
  end

  @doc """
  Generate TypeScript interfaces for all pages in a controller.

  Takes a controller module that uses NbSerializer.Inertia.Controller and generates
  TypeScript interfaces for each declared page, properly extending shared props
  interfaces if any are registered.

  Returns either a single concatenated string (if `as_list: false`) or a list
  of {page_name, page_config, typescript} tuples (if `as_list: true`).

  ## Examples

      # Get concatenated string
      typescript = NbTs.Interface.generate_page_types(MyAppWeb.UserController)

      # Get list of individual page interfaces
      pages = NbTs.Interface.generate_page_types(MyAppWeb.UserController, as_list: true)
  """
  def generate_page_types(controller_module, opts \\ []) do
    as_list = Keyword.get(opts, :as_list, false)

    # Get shared modules registered with inertia_shared
    shared_modules =
      if function_exported?(controller_module, :__inertia_shared_modules__, 0) do
        controller_module.__inertia_shared_modules__()
      else
        []
      end

    # Get all pages from the controller
    pages =
      if function_exported?(controller_module, :__inertia_pages__, 0) do
        controller_module.__inertia_pages__()
      else
        %{}
      end

    # Get inline shared props (from inertia_shared do...end)
    inline_shared_props =
      if function_exported?(controller_module, :inertia_shared_props, 0) do
        controller_module.inertia_shared_props()
      else
        []
      end

    # Generate interface for each page
    results =
      pages
      |> Enum.map(fn {page_name, page_config} ->
        typescript =
          generate_page_interface(page_name, page_config, shared_modules, inline_shared_props)

        {page_name, page_config, typescript}
      end)

    if as_list do
      results
    else
      results
      |> Enum.map_join("\n\n", fn {_, _, typescript} -> typescript end)
    end
  end

  @doc """
  Generate TypeScript interface for a single Inertia page.

  This function is used internally by `generate_page_types/2` but can also be
  called directly for testing or custom type generation.

  ## Parameters

    - `page_name` - The atom name of the page (e.g., `:users_index`)
    - `page_config` - The page configuration map with component and props
    - `shared_modules` - List of shared props modules
    - `inline_shared_props` - List of inline shared props declared in the controller

  ## Options in page_config

    - `:index_signature` - When `true`, adds `[key: string]: unknown;` to the interface.
      This is useful for Inertia's `usePage<T>()` hook which may include additional
      props not explicitly declared. Defaults to `false`.

  ## Examples

      page_config = %{
        component: "Users/Index",
        props: [...],
        index_signature: true
      }

      typescript = NbTs.Interface.generate_page_interface(:users_index, page_config, [], [])
  """
  def generate_page_interface(_page_name, page_config, shared_modules, inline_shared_props) do
    # Build interface name from component name
    component_name = page_config.component
    interface_name = component_name_to_interface(component_name)

    # Combine inline shared props with page props
    # Inline shared props come first to maintain ordering
    all_props = inline_shared_props ++ page_config.props

    # Build extends clause if there are shared modules
    extends_clause =
      if shared_modules == [] do
        ""
      else
        shared_interface_names =
          shared_modules
          |> Enum.map_join(", ", &shared_props_interface_name/1)

        " extends #{shared_interface_names}"
      end

    # Convert all props (inline shared + page props) to TypeScript fields
    {fields, imports} = build_page_props_fields(all_props)

    # Add imports for shared props interfaces if needed
    shared_imports =
      if shared_modules == [] do
        []
      else
        Enum.map(shared_modules, fn module ->
          shared_props_interface_name(module)
        end)
      end

    all_imports = Enum.uniq(imports ++ shared_imports)

    # Render imports
    import_statements = render_imports(all_imports)

    # Render fields
    field_lines = Enum.map_join(fields, "\n", &render_field/1)

    # Add index signature if requested
    index_signature =
      if Map.get(page_config, :index_signature, false) do
        "\n  [key: string]: unknown;"
      else
        ""
      end

    # Add doc comment with component name
    doc_comment = """
    /**
     * Props for #{component_name}
     *
     * Generated from NbSerializer Inertia page declaration
     */
    """

    typescript = """
    #{import_statements}#{if import_statements != "", do: "\n"}#{doc_comment}export interface #{interface_name}#{extends_clause} {
    #{field_lines}#{index_signature}
    }
    """

    typescript
  end

  defp shared_props_interface_name(module) do
    # NbSerializer.Inertia.SharedProps.Shopify -> ShopifyProps
    # MyAppWeb.InertiaShared.Locale -> LocaleProps
    module
    |> Module.split()
    |> List.last()
    |> Kernel.<>("Props")
  end

  defp component_name_to_interface(component_name) do
    # "Users/Index" -> "UsersIndexProps"
    # "Admin/Dashboard" -> "AdminDashboardProps"
    component_name
    |> String.replace("/", "")
    |> String.replace(" ", "")
    |> Kernel.<>("Props")
  end

  defp build_shared_props_fields(props) do
    {fields, imports} =
      Enum.reduce(props, {[], []}, fn prop_config, {fields_acc, imports_acc} ->
        {field, new_imports} = prop_config_to_field(prop_config)
        {[field | fields_acc], imports_acc ++ new_imports}
      end)

    {Enum.reverse(fields), Enum.uniq(imports)}
  end

  defp build_page_props_fields(props) do
    {fields, imports} =
      Enum.reduce(props, {[], []}, fn prop_config, {fields_acc, imports_acc} ->
        {field, new_imports} = prop_config_to_field(prop_config)
        {[field | fields_acc], imports_acc ++ new_imports}
      end)

    {Enum.reverse(fields), Enum.uniq(imports)}
  end

  defp prop_config_to_field(prop_config) do
    name = prop_config.name
    opts = Map.get(prop_config, :opts, [])
    optional = Keyword.get(opts, :optional, false)
    lazy = Keyword.get(opts, :lazy, false)
    defer = Keyword.get(opts, :defer, false)
    nullable = Keyword.get(opts, :nullable, false)

    # Determine the TypeScript type and imports
    {ts_type, imports} =
      cond do
        # Check if type is in opts (e.g., prop(:name, type: "...", nullable: true))
        Keyword.has_key?(opts, :type) ->
          type = Keyword.get(opts, :type)

          # Check if type is a custom string
          if is_binary(type) do
            {type, []}
          else
            {elixir_type_to_typescript(type), []}
          end

        # Has a serializer module
        Map.has_key?(prop_config, :serializer) ->
          serializer = prop_config.serializer

          cond do
            # Check if it's a custom type string
            is_binary(serializer) ->
              {serializer, []}

            # Check if it's a primitive type
            serializer in [:string, :integer, :float, :boolean, :number, :map, :list, :datetime] ->
              {elixir_type_to_typescript(serializer), []}

            # It's a module - extract interface name
            true ->
              type_name = interface_name(serializer)
              {type_name, [type_name]}
          end

        # Has a primitive type
        Map.has_key?(prop_config, :type) ->
          type = prop_config.type

          # Check if type is a custom string
          if is_binary(type) do
            {type, []}
          else
            {elixir_type_to_typescript(type), []}
          end

        # Default to any
        true ->
          {"any", []}
      end

    # Handle list types
    list = Keyword.get(opts, :list, false)
    ts_type = if list, do: "#{ts_type}[]", else: ts_type

    # Apply nullable modifier if needed
    ts_type = if nullable, do: "#{ts_type} | null", else: ts_type

    # Build field
    field = %{
      name: name,
      type: ts_type,
      optional: optional || lazy || defer,
      nullable: false,
      comment: nil
    }

    {field, imports}
  end

  defp elixir_type_to_typescript(type) do
    case type do
      :string -> "string"
      :integer -> "number"
      :float -> "number"
      :number -> "number"
      :boolean -> "boolean"
      :datetime -> "string"
      :map -> "Record<string, any>"
      :list -> "any[]"
      _ -> "any"
    end
  end
end
