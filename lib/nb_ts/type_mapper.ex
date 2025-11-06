defmodule NbTs.TypeMapper do
  @moduledoc """
  Maps field type options to TypeScript types.
  """

  @doc """
  Converts a field's type options to TypeScript type string.
  """
  def to_typescript(%{type: :string}), do: "string"
  def to_typescript(%{type: :integer}), do: "number"
  def to_typescript(%{type: :number}), do: "number"
  def to_typescript(%{type: :boolean}), do: "boolean"
  def to_typescript(%{type: :decimal}), do: "number"
  def to_typescript(%{type: :uuid}), do: "string"
  def to_typescript(%{type: :date}), do: "string"
  def to_typescript(%{type: :datetime}), do: "string"
  def to_typescript(%{type: :any}), do: "any"

  # Handle validated TypeScript types (from ~TS sigil)
  def to_typescript(%{type: type, custom: true, typescript_validated: true})
      when is_binary(type) do
    # Use validated TypeScript type as-is
    type
  end

  # Handle legacy custom types (without validation)
  def to_typescript(%{type: type, custom: true}) when is_binary(type) do
    # Legacy: warn about unvalidated custom types in dev
    if Mix.env() in [:dev, :test] do
      IO.warn("""
      Custom TypeScript type without ~TS validation: #{inspect(type)}

      Consider using ~TS sigil for compile-time validation:
        field :my_field, :typescript, type: ~TS"#{type}"

      This ensures TypeScript syntax is valid at compile time.
      """)
    end

    type
  end

  def to_typescript(%{enum: values}) when is_list(values) do
    values |> Enum.map(&inspect/1) |> Enum.join(" | ")
  end

  def to_typescript(%{polymorphic: types}) when is_list(types) do
    types |> Enum.map(&to_string/1) |> Enum.join(" | ")
  end

  # Handle new unified syntax: list: [enum: [...]]
  def to_typescript(%{list: list_opts}) when is_list(list_opts) do
    cond do
      # list: [enum: [...]] -> ("value1" | "value2")[]
      Keyword.has_key?(list_opts, :enum) ->
        enum_values = Keyword.get(list_opts, :enum)
        enum_union = enum_values |> Enum.map(&inspect/1) |> Enum.join(" | ")
        "(#{enum_union})[]"

      # list: :string -> string[] (but this is handled differently via apply_modifiers)
      true ->
        "unknown"
    end
  end

  def to_typescript(_), do: "unknown"

  @doc """
  Normalizes type options from field macro.
  """
  def normalize_type_opts(opts) when is_list(opts) do
    type = Keyword.get(opts, :type)
    enum = Keyword.get(opts, :enum)
    list = Keyword.get(opts, :list, false)
    nullable = Keyword.get(opts, :nullable, false)
    optional = Keyword.get(opts, :optional, false)
    polymorphic = Keyword.get(opts, :polymorphic)
    typescript_validated = Keyword.get(opts, :typescript_validated, false)
    custom = Keyword.get(opts, :custom, false)

    %{
      type: type,
      enum: enum,
      list: list,
      nullable: nullable,
      optional: optional,
      polymorphic: polymorphic,
      typescript_validated: typescript_validated,
      custom: custom || is_binary(type)
    }
  end

  @doc """
  Applies list and nullable modifiers to a base type.
  """
  def apply_modifiers(base_type, type_info) do
    type = if Map.get(type_info, :list), do: "Array<#{base_type}>", else: base_type
    if Map.get(type_info, :nullable), do: "#{type} | null", else: type
  end
end
