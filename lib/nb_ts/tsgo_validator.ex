defmodule NbTs.TsgoValidator do
  @moduledoc """
  TypeScript validation using tsgo (native TypeScript compiler).

  Provides a simple interface to validate TypeScript code using the pooled
  tsgo processes managed by NbTs.TsgoPool.

  ## Examples

      iex> NbTs.TsgoValidator.validate("const x: number = 5")
      {:ok, "const x: number = 5"}

      iex> NbTs.TsgoValidator.validate("const x: number = 'bad'")
      {:error, "...Type 'string' is not assignable..."}
  """

  @doc """
  Validates TypeScript code.

  ## Options

    * `:timeout` - Validation timeout in milliseconds (default: 30_000)

  ## Examples

      validate("const x: number = 5")
      validate(code, timeout: 10_000)
  """
  @spec validate(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def validate(typescript_code, opts \\ []) do
    # Ensure nb_ts application is started (important during compilation of dependent projects)
    Application.ensure_all_started(:nb_ts)

    NbTs.TsgoPool.validate(typescript_code, opts)
  end
end
