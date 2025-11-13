defmodule NbTs.GeneratorOptions do
  @moduledoc """
  Options for the TypeScript generator.

  This struct encapsulates all configuration options that can be passed
  to the generator functions.
  """

  @type t :: %__MODULE__{
          output_dir: Path.t(),
          validate: boolean(),
          verbose: boolean(),
          incremental: boolean()
        }

  defstruct output_dir: nil,
            validate: false,
            verbose: false,
            incremental: true

  @doc """
  Creates a new GeneratorOptions struct from a keyword list.

  Uses NbTs.Config for defaults when options are not provided.

  ## Examples

      iex> NbTs.GeneratorOptions.new()
      %NbTs.GeneratorOptions{
        output_dir: "assets/js/types",
        validate: false,
        verbose: false,
        incremental: true
      }

      iex> NbTs.GeneratorOptions.new(output_dir: "lib/types", verbose: true)
      %NbTs.GeneratorOptions{
        output_dir: "lib/types",
        validate: false,
        verbose: true,
        incremental: true
      }

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      output_dir: Keyword.get(opts, :output_dir, NbTs.Config.output_dir()),
      validate: Keyword.get(opts, :validate, NbTs.Config.validate?()),
      verbose: Keyword.get(opts, :verbose, NbTs.Config.verbose?()),
      incremental: Keyword.get(opts, :incremental, true)
    }
  end

  @doc """
  Converts GeneratorOptions to a keyword list.

  Useful for passing options to functions that expect keyword lists.

  ## Examples

      iex> opts = NbTs.GeneratorOptions.new(verbose: true)
      iex> NbTs.GeneratorOptions.to_keyword(opts)
      [output_dir: "assets/js/types", validate: false, verbose: true, incremental: true]

  """
  @spec to_keyword(t()) :: keyword()
  def to_keyword(%__MODULE__{} = opts) do
    [
      output_dir: opts.output_dir,
      validate: opts.validate,
      verbose: opts.verbose,
      incremental: opts.incremental
    ]
  end

  @doc """
  Validates the options.

  Returns `{:ok, opts}` if valid, `{:error, reason}` otherwise.

  ## Examples

      iex> opts = NbTs.GeneratorOptions.new()
      iex> NbTs.GeneratorOptions.validate(opts)
      {:ok, opts}

      iex> opts = %NbTs.GeneratorOptions{output_dir: ""}
      iex> NbTs.GeneratorOptions.validate(opts)
      {:error, "output_dir must be a non-empty string"}

  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{output_dir: output_dir} = opts) do
    cond do
      !is_binary(output_dir) or String.length(output_dir) == 0 ->
        {:error, "output_dir must be a non-empty string"}

      true ->
        {:ok, opts}
    end
  end

  @doc """
  Validates the options, raising on error.

  Returns the options if valid, raises otherwise.

  ## Examples

      iex> opts = NbTs.GeneratorOptions.new()
      iex> NbTs.GeneratorOptions.validate!(opts)
      %NbTs.GeneratorOptions{...}

  """
  @spec validate!(t()) :: t() | no_return()
  def validate!(%__MODULE__{} = opts) do
    case validate(opts) do
      {:ok, opts} ->
        opts

      {:error, reason} ->
        raise ArgumentError, "Invalid generator options: #{reason}"
    end
  end
end
