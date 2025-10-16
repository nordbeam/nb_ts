defmodule NbTs.IndexManager do
  @moduledoc """
  Manages incremental updates to the index.ts export file.

  Instead of regenerating the entire index, tracks existing exports
  and only adds/removes/updates changed entries.
  """

  @doc """
  Update index.ts incrementally based on changed files.

  ## Options

  - `:added` - List of {interface_name, filename} tuples to add
  - `:removed` - List of interface_names to remove
  - `:updated` - List of {interface_name, filename} tuples to update

  ## Examples

      IndexManager.update_index("/path/to/types",
        added: [{"User", "User"}],
        removed: ["OldType"],
        updated: [{"Post", "PostV2"}]
      )
  """
  def update_index(output_dir, opts) do
    index_path = Path.join(output_dir, "index.ts")

    # Read existing index or create empty
    existing_exports = read_existing_exports(index_path)

    # Apply changes
    new_exports =
      existing_exports
      |> remove_exports(Keyword.get(opts, :removed, []))
      |> add_exports(Keyword.get(opts, :added, []))
      |> update_exports(Keyword.get(opts, :updated, []))

    # Write updated index
    write_index(index_path, new_exports)

    {:ok, map_size(new_exports)}
  end

  @doc """
  Rebuild the entire index from scratch.

  Used for initial generation or when index becomes corrupted.
  """
  def rebuild_index(output_dir) do
    # Scan directory for all .ts files (except index.ts)
    files =
      output_dir
      |> Path.join("*.ts")
      |> Path.wildcard()
      |> Enum.reject(&String.ends_with?(&1, "index.ts"))

    exports =
      Enum.map(files, fn filepath ->
        filename = Path.basename(filepath, ".ts")

        # Extract the actual interface/type name from the file content
        interface_name = extract_interface_name(filepath) || filename

        {interface_name, filename}
      end)

    update_index(output_dir, added: exports)
  end

  # Extract interface name from a TypeScript file
  # Returns the name of the first exported interface or type
  defp extract_interface_name(filepath) do
    case File.read(filepath) do
      {:ok, content} ->
        # Match: export interface InterfaceName or export type TypeName
        case Regex.run(~r/export (?:interface|type) (\w+)/, content) do
          [_, name] -> name
          nil -> nil
        end

      {:error, _} ->
        nil
    end
  end

  @doc """
  Parse an export line from index.ts.

  Returns a list with a single {name, filename} tuple, or empty list if invalid.

  ## Examples

      iex> parse_export_line(~s(export type { User } from "./User";))
      [{"User", "User"}]

      iex> parse_export_line("// comment")
      []
  """
  def parse_export_line(line) do
    # Parse: export type { InterfaceName } from "./InterfaceName";
    case Regex.run(~r/export type \{ (\w+) \} from "\.\/(.+)";/, line) do
      [_, name, filename] -> [{name, filename}]
      nil -> []
    end
  end

  # Private helpers

  defp read_existing_exports(index_path) do
    if File.exists?(index_path) do
      index_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.flat_map(&parse_export_line/1)
      |> Map.new()
    else
      %{}
    end
  end

  defp remove_exports(exports_map, names_to_remove) do
    Enum.reduce(names_to_remove, exports_map, fn name, acc ->
      Map.delete(acc, name)
    end)
  end

  defp add_exports(exports_map, entries_to_add) do
    Enum.reduce(entries_to_add, exports_map, fn {name, filename}, acc ->
      Map.put(acc, name, filename)
    end)
  end

  defp update_exports(exports_map, entries_to_update) do
    add_exports(exports_map, entries_to_update)
  end

  defp write_index(index_path, exports_map) do
    content =
      exports_map
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map_join("\n", fn {name, filename} ->
        ~s(export type { #{name} } from "./#{filename}";)
      end)

    File.write!(index_path, content <> "\n")
  end
end
