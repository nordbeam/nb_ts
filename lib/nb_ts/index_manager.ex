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
      Enum.flat_map(files, fn filepath ->
        filename = Path.basename(filepath, ".ts")

        # Extract all interface/type names from the file content
        interface_names = extract_interface_names(filepath)

        # If no interfaces found, use filename as fallback
        names = if Enum.empty?(interface_names), do: [filename], else: interface_names

        Enum.map(names, fn name -> {name, filename} end)
      end)
      # Convert to map to ensure uniqueness
      |> Map.new()

    # Write index directly (don't use update_index which merges with existing)
    index_path = Path.join(output_dir, "index.ts")
    write_index(index_path, exports)

    {:ok, map_size(exports)}
  end

  # Extract all interface/type names from a TypeScript file
  # Returns a list of exported interface/type names
  defp extract_interface_names(filepath) do
    case File.read(filepath) do
      {:ok, content} ->
        # Match all: export interface InterfaceName or export type TypeName
        Regex.scan(~r/export (?:interface|type) (\w+)/, content)
        |> Enum.map(fn [_, name] -> name end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Parse an export line from index.ts.

  Returns a list of {name, filename} tuples (one for each interface in the export).

  ## Examples

      iex> parse_export_line(~s(export type { User } from "./User";))
      [{"User", "User"}]

      iex> parse_export_line(~s(export type { User, Post } from "./Types";))
      [{"User", "Types"}, {"Post", "Types"}]

      iex> parse_export_line("// comment")
      []
  """
  def parse_export_line(line) do
    # Parse: export type { Name1, Name2, ... } from "./filename";
    case Regex.run(~r/export type \{ (.+?) \} from "\.\/(.+)";/, line) do
      [_, names_str, filename] ->
        # Split the interface names by comma and trim whitespace
        names_str
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(fn name -> {name, filename} end)

      nil ->
        []
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
    # Group interfaces by filename so multiple interfaces from the same file
    # are exported together (e.g., SpacesNewProps and SpacesNewFormInputs)
    content =
      exports_map
      |> Enum.group_by(fn {_name, filename} -> filename end, fn {name, _filename} -> name end)
      |> Enum.sort_by(fn {filename, _names} -> filename end)
      |> Enum.map_join("\n", fn {filename, names} ->
        # Sort interface names alphabetically for consistent output
        sorted_names = Enum.sort(names)
        names_str = Enum.join(sorted_names, ", ")
        ~s(export type { #{names_str} } from "./#{filename}";)
      end)

    File.write!(index_path, content <> "\n")
  end
end
