defmodule NbTs.TableInterface do
  @moduledoc """
  Builds TypeScript row interfaces from NbFlop table type metadata.

  Generates TypeScript interfaces that describe the shape of table row data
  as it appears on the frontend (after NbFlop's transform_row processing).
  """

  @column_type_map %{
    text: "string",
    badge: "string",
    numeric: "number",
    date: "string",
    datetime: "string",
    boolean: "boolean",
    image: "string"
  }

  @extra_field_type_map %{
    string: "string",
    number: "number",
    boolean: "boolean"
  }

  @doc """
  Generates a TypeScript interface file for a NbFlop table module.

  Returns `{interface_name, filename}` tuple.

  ## Examples

      {name, file} = NbTs.TableInterface.generate(MyAppWeb.Tables.WebhooksTable, "assets/js/types")
      # => {"WebhooksRow", "WebhooksRow.ts"}
  """
  def generate(table_module, output_dir, verbose? \\ false) do
    metadata = table_module.__nb_flop_type_metadata__()
    interface_name = derive_interface_name(table_module)
    filename = "#{interface_name}.ts"
    filepath = Path.join(output_dir, filename)

    typescript = build_typescript(interface_name, metadata)
    File.write!(filepath, typescript)

    if verbose? do
      IO.puts("  Generated #{filename}")
    end

    {interface_name, filename}
  end

  @doc """
  Derives the TypeScript interface name from a table module.

  ## Examples

      iex> NbTs.TableInterface.derive_interface_name(MyAppWeb.Tables.WebhooksTable)
      "WebhooksRow"

      iex> NbTs.TableInterface.derive_interface_name(MyAppWeb.Tables.ApiKeysTable)
      "ApiKeysRow"
  """
  def derive_interface_name(table_module) do
    table_module
    |> Module.split()
    |> List.last()
    |> String.replace(~r/Table$/, "")
    |> Kernel.<>("Row")
  end

  @doc """
  Builds the full TypeScript interface string from metadata.
  """
  def build_typescript(interface_name, metadata) do
    column_fields = build_column_fields(metadata.columns)
    extra_fields = build_extra_fields(metadata.extra_fields)

    all_fields =
      [{"id", "string", false}] ++ column_fields ++ extra_fields

    # Sort fields alphabetically by name, deduplicate (id might appear in columns too)
    sorted_fields =
      all_fields
      |> Enum.uniq_by(fn {name, _type, _nullable} -> name end)
      |> Enum.sort_by(fn {name, _type, _nullable} -> name end)

    field_lines =
      Enum.map_join(sorted_fields, "\n", fn {name, type, nullable} ->
        ts_type = if nullable, do: "#{type} | null", else: type
        "  #{name}: #{ts_type};"
      end)

    """
    /**
     * Row type for #{interface_name} table
     *
     * Generated from NbFlop table definition
     */
    export interface #{interface_name} {
    #{field_lines}
    }
    """
  end

  defp build_column_fields(columns) do
    Enum.map(columns, fn col ->
      name = camelize(col.key)

      type =
        if col.ts_type do
          col.ts_type
        else
          Map.get(@column_type_map, col.type, "unknown")
        end

      {name, type, col.nullable}
    end)
  end

  defp build_extra_fields(extra_fields) do
    Enum.map(extra_fields, fn field ->
      name = camelize(field.key)
      type = resolve_extra_field_type(field)
      {name, type, field.nullable}
    end)
  end

  defp resolve_extra_field_type(%{type: :map, fields: fields}) when is_list(fields) do
    inner =
      fields
      |> Enum.map_join("; ", fn {key, type} ->
        ts_type = Map.get(@extra_field_type_map, type, "unknown")
        "#{camelize(key)}: #{ts_type}"
      end)

    "{ #{inner} }"
  end

  defp resolve_extra_field_type(%{type: :map}) do
    "Record<string, unknown>"
  end

  defp resolve_extra_field_type(%{type: type}) do
    Map.get(@extra_field_type_map, type, "unknown")
  end

  defp camelize(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map_join(fn
      {word, 0} -> word
      {word, _} -> String.capitalize(word)
    end)
  end
end
