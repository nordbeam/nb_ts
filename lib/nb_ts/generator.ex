defmodule NbTs.Generator do
  @moduledoc """
  TypeScript validation using oxc parser (primary) with Elixir fallback.

  Validates generated TypeScript code to ensure syntactic correctness.
  Uses the oxc parser via NIF when available, falls back to pattern matching.
  """

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
end
