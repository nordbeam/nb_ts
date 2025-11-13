defmodule NbTs.Field do
  @moduledoc """
  Represents a TypeScript field in an interface.

  This struct encapsulates all the information needed to generate
  a TypeScript field declaration, including its name, type, and modifiers.
  """

  @type typescript_type :: String.t()

  @type t :: %__MODULE__{
          name: String.t(),
          type: typescript_type(),
          optional: boolean(),
          nullable: boolean(),
          description: String.t() | nil
        }

  defstruct [
    :name,
    :type,
    optional: false,
    nullable: false,
    description: nil
  ]

  @doc """
  Creates a new Field struct.

  ## Examples

      iex> NbTs.Field.new("id", "number")
      %NbTs.Field{name: "id", type: "number", optional: false, nullable: false}

      iex> NbTs.Field.new("name", "string", optional: true)
      %NbTs.Field{name: "name", type: "string", optional: true, nullable: false}

  """
  @spec new(String.t(), typescript_type(), keyword()) :: t()
  def new(name, type, opts \\ []) do
    %__MODULE__{
      name: name,
      type: type,
      optional: Keyword.get(opts, :optional, false),
      nullable: Keyword.get(opts, :nullable, false),
      description: Keyword.get(opts, :description)
    }
  end

  @doc """
  Converts a field to its TypeScript string representation.

  ## Examples

      iex> field = NbTs.Field.new("id", "number")
      iex> NbTs.Field.to_typescript(field)
      "id: number;"

      iex> field = NbTs.Field.new("name", "string", optional: true)
      iex> NbTs.Field.to_typescript(field)
      "name?: string;"

      iex> field = NbTs.Field.new("email", "string", nullable: true)
      iex> NbTs.Field.to_typescript(field)
      "email: string | null;"

      iex> field = NbTs.Field.new("tags", "string", optional: true, nullable: true)
      iex> NbTs.Field.to_typescript(field)
      "tags?: string | null;"

  """
  @spec to_typescript(t()) :: String.t()
  def to_typescript(%__MODULE__{} = field) do
    name_part = if field.optional, do: "#{field.name}?", else: field.name
    type_part = if field.nullable, do: "#{field.type} | null", else: field.type

    "#{name_part}: #{type_part};"
  end

  @doc """
  Returns whether the field is required (not optional).

  ## Examples

      iex> field = NbTs.Field.new("id", "number")
      iex> NbTs.Field.required?(field)
      true

      iex> field = NbTs.Field.new("name", "string", optional: true)
      iex> NbTs.Field.required?(field)
      false

  """
  @spec required?(t()) :: boolean()
  def required?(%__MODULE__{optional: optional}), do: not optional
end
