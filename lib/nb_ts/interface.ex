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

    sorted_fields =
      fields |> Enum.reverse() |> Enum.sort_by(fn field -> camelize_atom(field.name) end)

    {sorted_fields, Enum.uniq(imports)}
  end

  defp resolve_field_type(type_info, _visited) do
    cond do
      # Handle relationship types
      serializer = type_info[:serializer] ->
        type_name = interface_name(serializer)
        module_name = serializer |> Module.split() |> List.last()
        # Return tuple of {interface_name, module_name} for correct import paths
        {apply_modifiers(type_name, type_info), [{type_name, module_name}]}

      # Handle polymorphic types
      type_info[:polymorphic] ->
        type_union = type_info[:polymorphic] |> Enum.map_join(" | ", &to_string/1)
        {type_union, []}

      # Handle new unified syntax: list: :string (or other primitive)
      # When list contains a primitive type atom like :string, :number, etc.
      # Exclude boolean atoms (true/false) which indicate old format
      type_info[:list] && is_atom(type_info[:list]) && !is_boolean(type_info[:list]) &&
          !is_module?(type_info[:list]) ->
        primitive = type_info[:list]
        base_type = elixir_type_to_typescript(primitive)
        # Build Array<type> and apply nullable modifier if needed
        array_type = "Array<#{base_type}>"
        type = if type_info[:nullable], do: "#{array_type} | null", else: array_type
        {type, []}

      # Handle new unified syntax: list: SerializerModule
      # When list contains a module, treat it as a list of serializers
      is_atom(type_info[:list]) && is_module?(type_info[:list]) ->
        serializer = type_info[:list]
        type_name = interface_name(serializer)
        module_name = serializer |> Module.split() |> List.last()
        # Build Array<TypeName> and add import
        base_type = "Array<#{type_name}>"
        type = if type_info[:nullable], do: "#{base_type} | null", else: base_type
        {type, [{type_name, module_name}]}

      # Handle new unified syntax: list: [enum: [...]]
      # TypeMapper returns the complete type already, so don't apply modifiers
      is_list(type_info[:list]) && Keyword.has_key?(type_info[:list], :enum) ->
        base_type = NbTs.TypeMapper.to_typescript(type_info)
        # Only apply nullable modifier if needed (list modifier already applied by TypeMapper)
        type = if type_info[:nullable], do: "#{base_type} | null", else: base_type
        {type, []}

      # Regular types
      true ->
        base_type = NbTs.TypeMapper.to_typescript(type_info)
        {apply_modifiers(base_type, type_info), []}
    end
  end

  # Helper to check if an atom is a module
  defp is_module?(atom) when is_atom(atom) do
    # Check if it's a valid module by trying to get module info
    # Atoms like :string, :number, :boolean are not modules
    # Module atoms like MyApp.Serializer are modules
    case Atom.to_string(atom) do
      "Elixir." <> _ -> true
      _ -> false
    end
  end

  defp is_module?(_), do: false

  defp apply_modifiers(base_type, type_info) do
    type = if type_info[:list], do: "Array<#{base_type}>", else: base_type
    if type_info[:nullable], do: "#{type} | null", else: type
  end

  defp render_imports([]), do: ""

  defp render_imports(imports) do
    imports
    |> Enum.map_join("\n", fn
      # Handle new tuple format {interface_name, module_name}
      {interface_name, module_name} ->
        ~s(import type { #{interface_name} } from "./#{module_name}";)

      # Handle legacy string format (for shared props)
      import_name when is_binary(import_name) ->
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
    # Forms are already stored per-page in page_config.forms
    results =
      pages
      |> Enum.map(fn {page_name, page_config} ->
        typescript =
          generate_page_interface(
            page_name,
            page_config,
            shared_modules,
            inline_shared_props
          )

        # Return page_config with its own forms intact
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
  def generate_page_interface(page_name, page_config, shared_modules, inline_shared_props) do
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
          interface = shared_props_interface_name(module)
          # Shared props use interface name as filename too
          {interface, interface}
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

    props_interface = """
    #{import_statements}#{if import_statements != "", do: "\n"}#{doc_comment}export interface #{interface_name}#{extends_clause} {
    #{field_lines}#{index_signature}
    }
    """

    # Generate FormInputs interface if forms are present
    forms = Map.get(page_config, :forms, %{})
    forms_interface = generate_forms_interface(page_name, forms, component_name)

    # Combine Props and FormInputs interfaces
    typescript =
      if forms_interface == "" do
        props_interface
      else
        props_interface <> "\n\n" <> forms_interface
      end

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

    sorted_fields =
      fields |> Enum.reverse() |> Enum.sort_by(fn field -> camelize_atom(field.name) end)

    {sorted_fields, Enum.uniq(imports)}
  end

  defp build_page_props_fields(props) do
    {fields, imports} =
      Enum.reduce(props, {[], []}, fn prop_config, {fields_acc, imports_acc} ->
        {field, new_imports} = prop_config_to_field(prop_config)
        {[field | fields_acc], imports_acc ++ new_imports}
      end)

    sorted_fields =
      fields |> Enum.reverse() |> Enum.sort_by(fn field -> camelize_atom(field.name) end)

    {sorted_fields, Enum.uniq(imports)}
  end

  defp prop_config_to_field(prop_config) do
    name = prop_config.name
    opts = Map.get(prop_config, :opts, [])
    optional = Keyword.get(opts, :optional, false)
    lazy = Keyword.get(opts, :lazy, false)
    defer = Keyword.get(opts, :defer, false)
    nullable = Keyword.get(opts, :nullable, false)

    # Check for unified syntax in opts first
    {ts_type, imports, already_has_list_modifier} =
      cond do
        # Unified syntax: list: SerializerModule
        # e.g., prop(:users, list: UserSerializer)
        Keyword.has_key?(opts, :list) && is_atom(Keyword.get(opts, :list)) &&
            is_module?(Keyword.get(opts, :list)) ->
          serializer = Keyword.get(opts, :list)
          type_name = interface_name(serializer)
          module_name = serializer |> Module.split() |> List.last()
          {"#{type_name}[]", [{type_name, module_name}], true}

        # Unified syntax: list: :string (or other primitive)
        # e.g., prop(:tags, list: :string)
        Keyword.has_key?(opts, :list) &&
            is_atom(Keyword.get(opts, :list)) ->
          primitive = Keyword.get(opts, :list)
          base_type = elixir_type_to_typescript(primitive)
          {"#{base_type}[]", [], true}

        # Unified syntax: list: [enum: [...]]
        # e.g., prop(:roles, list: [enum: ["admin", "user"]])
        Keyword.has_key?(opts, :list) && is_list(Keyword.get(opts, :list)) &&
            Keyword.has_key?(Keyword.get(opts, :list), :enum) ->
          enum_values = Keyword.get(opts, :list) |> Keyword.get(:enum)
          enum_union = enum_values |> Enum.map(&inspect/1) |> Enum.join(" | ")
          {"(#{enum_union})[]", [], true}

        # Unified syntax: enum: [...]
        # e.g., prop(:status, enum: ["active", "inactive"])
        Keyword.has_key?(opts, :enum) ->
          enum_values = Keyword.get(opts, :enum)
          enum_union = enum_values |> Enum.map(&inspect/1) |> Enum.join(" | ")
          {enum_union, [], false}

        # Check if type is in opts (e.g., prop(:name, type: "...", nullable: true))
        Keyword.has_key?(opts, :type) ->
          type = Keyword.get(opts, :type)

          # Check if type is a ~TS sigil (returns {:typescript_validated, "..."})
          ts_type =
            case type do
              {:typescript_validated, ts_string} when is_binary(ts_string) ->
                ts_string

              type when is_binary(type) ->
                type

              _ ->
                elixir_type_to_typescript(type)
            end

          {ts_type, [], false}

        # Has a serializer module
        Map.has_key?(prop_config, :serializer) ->
          serializer = prop_config.serializer

          ts_type =
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
                module_name = serializer |> Module.split() |> List.last()
                {type_name, [{type_name, module_name}]}
            end

          case ts_type do
            {type, imports} -> {type, imports, false}
            type when is_binary(type) -> {type, [], false}
          end

        # Has a primitive type
        Map.has_key?(prop_config, :type) ->
          type = prop_config.type

          # Check if type is a ~TS sigil (returns {:typescript_validated, "..."})
          ts_type =
            case type do
              {:typescript_validated, ts_string} when is_binary(ts_string) ->
                ts_string

              type when is_binary(type) ->
                type

              _ ->
                elixir_type_to_typescript(type)
            end

          {ts_type, [], false}

        # Default to any
        true ->
          {"any", [], false}
      end

    # Handle old-style list modifier (only if not already handled by unified syntax)
    # This maintains backward compatibility with prop(:users, UserSerializer, list: true)
    ts_type =
      if !already_has_list_modifier && Keyword.get(opts, :list, false) == true do
        "#{ts_type}[]"
      else
        ts_type
      end

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

  # is_module?/1 helper is defined earlier in the file (around line 179)

  defp elixir_type_to_typescript(type) do
    case type do
      :string -> "string"
      :integer -> "number"
      :float -> "number"
      :number -> "number"
      :boolean -> "boolean"
      :datetime -> "string"
      :date -> "string"
      :any -> "any"
      :map -> "Record<string, any>"
      :list -> "any[]"
      _ -> "any"
    end
  end

  @doc """
  Generate TypeScript FormInputs interface for form definitions.

  Takes a page name, form definitions map, and component name, and generates
  a TypeScript interface for form inputs.

  Returns empty string if forms map is empty or nil.
  """
  def generate_forms_interface(_page_name, nil, _component_name), do: ""
  def generate_forms_interface(_page_name, forms, _component_name) when forms == %{}, do: ""

  def generate_forms_interface(page_name, forms, component_name) when is_map(forms) do
    # Generate interface name from component name
    interface_name = page_name_to_form_inputs_interface(page_name, component_name)

    # Generate form fields
    form_fields = generate_form_fields(forms)

    # Build the interface
    doc_comment = """
    /**
     * Form inputs for #{component_name}
     */
    """

    """
    #{doc_comment}export interface #{interface_name} {
    #{form_fields}
    }
    """
  end

  @doc """
  Generate nested TypeScript object types for all forms.

  Takes a map of form definitions and returns formatted TypeScript fields.
  Respects the `:snake_case_params` config from `:nb_inertia` (defaults to true).

  When `snake_case_params: true`, generates camelCase TypeScript (frontend sends camelCase, backend converts).
  When `snake_case_params: false`, generates snake_case TypeScript (frontend sends snake_case, no conversion).
  """
  def generate_form_fields(forms) when is_map(forms) do
    camelize? = should_camelize_form_inputs?()

    forms
    |> Enum.map(fn {form_name, fields} ->
      # Conditionally camelize the form name
      form_field_name =
        if camelize?, do: camelize_atom(form_name), else: Atom.to_string(form_name)

      # Generate field definitions for this form
      field_defs = generate_field_definitions(fields, camelize?)

      # Return formatted form field
      "  #{form_field_name}: {\n#{field_defs}\n  };"
    end)
    |> Enum.join("\n")
  end

  @doc """
  Generate field definitions with proper TypeScript types and optional markers.

  Takes a list of field tuples and returns formatted TypeScript fields.
  Supports both regular fields {name, type, opts} and nested list fields {name, :list, opts, nested_fields}.
  """
  def generate_field_definitions(fields, camelize? \\ true) when is_list(fields) do
    fields
    |> Enum.map(fn field ->
      case field do
        # Handle nested list fields (4-tuple)
        {name, :list, opts, nested_fields} when is_list(nested_fields) ->
          # Conditionally camelize field name
          field_name = if camelize?, do: camelize_atom(name), else: Atom.to_string(name)

          # Check if field is optional
          optional_marker = if Keyword.get(opts, :optional, false), do: "?", else: ""

          # Generate nested object type
          nested_definitions = generate_nested_field_definitions(nested_fields, camelize?)

          # Format as Array<{ ... }>
          "    #{field_name}#{optional_marker}: Array<{\n#{nested_definitions}\n    }>;"

        # Handle fields with options (3-tuple)
        {name, type, opts} ->
          # Conditionally camelize field name
          field_name = if camelize?, do: camelize_atom(name), else: Atom.to_string(name)

          # Check if field is optional
          optional_marker = if Keyword.get(opts, :optional, false), do: "?", else: ""

          # Determine TypeScript type based on options
          ts_type =
            cond do
              # Handle enum: ["value1", "value2"]
              Keyword.has_key?(opts, :enum) ->
                enum_values = Keyword.get(opts, :enum)

                enum_values
                |> Enum.map(&"\"#{&1}\"")
                |> Enum.join(" | ")

              # Handle list: :string
              Keyword.has_key?(opts, :list) && is_atom(Keyword.get(opts, :list)) ->
                inner_type = Keyword.get(opts, :list)
                inner_ts_type = elixir_type_to_typescript(inner_type)
                "#{inner_ts_type}[]"

              # Handle list: [enum: [...]]
              Keyword.has_key?(opts, :list) && is_list(Keyword.get(opts, :list)) ->
                list_opts = Keyword.get(opts, :list)

                if Keyword.has_key?(list_opts, :enum) do
                  enum_values = Keyword.get(list_opts, :enum)

                  enum_union =
                    enum_values
                    |> Enum.map(&"\"#{&1}\"")
                    |> Enum.join(" | ")

                  "(#{enum_union})[]"
                else
                  "any[]"
                end

              # Regular type
              true ->
                elixir_type_to_typescript(type)
            end

          # Format field
          "    #{field_name}#{optional_marker}: #{ts_type};"
      end
    end)
    |> Enum.join("\n")
  end

  # Generate field definitions for nested fields within an array.
  # Similar to generate_field_definitions but with deeper indentation.
  defp generate_nested_field_definitions(fields, camelize?) when is_list(fields) do
    fields
    |> Enum.map(fn {name, type, opts} ->
      # Conditionally camelize field name
      field_name = if camelize?, do: camelize_atom(name), else: Atom.to_string(name)

      # Map Elixir type to TypeScript
      ts_type = elixir_type_to_typescript(type)

      # Check if field is optional
      optional_marker = if Keyword.get(opts, :optional, false), do: "?", else: ""

      # Format field with deeper indentation (6 spaces for nested)
      "      #{field_name}#{optional_marker}: #{ts_type};"
    end)
    |> Enum.join("\n")
  end

  # Check if form inputs should be camelized based on snake_case_params config
  # When snake_case_params is true (default), frontend sends camelCase and backend converts to snake_case
  # When snake_case_params is false, frontend sends snake_case and backend doesn't convert
  defp should_camelize_form_inputs? do
    Application.get_env(:nb_inertia, :snake_case_params, true)
  end

  @doc """
  Convert page name and component name to FormInputs interface name.

  Examples:
    - (:users_new, "Users/New") -> "UsersNewFormInputs"
    - (:settings, "Settings/Index") -> "SettingsIndexFormInputs"
  """
  def page_name_to_form_inputs_interface(_page_name, component_name) do
    # Use component name for consistency with Props interface
    component_name
    |> String.replace("/", "")
    |> String.replace(" ", "")
    |> Kernel.<>("FormInputs")
  end
end
