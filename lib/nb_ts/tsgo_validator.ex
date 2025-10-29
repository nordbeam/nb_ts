defmodule NbTs.TsgoValidator do
  @moduledoc """
  TypeScript validation stub (validation disabled).

  This module provides a stub interface that always returns success without
  performing any actual TypeScript validation.

  ## Examples

      iex> NbTs.TsgoValidator.validate("const x: number = 5")
      {:ok, "const x: number = 5"}

      iex> NbTs.TsgoValidator.validate("const x: number = 'bad'")
      {:ok, "const x: number = 'bad'"}
  """

  @doc """
  Validates TypeScript code (stubbed - no actual validation is performed).

  Always returns `{:ok, typescript_code}` without performing any validation.

  ## Options

    * `:timeout` - Ignored (kept for API compatibility)

  ## Examples

      validate("const x: number = 5")
      validate(code, timeout: 10_000)
  """
  @spec validate(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def validate(typescript_code, _opts \\ []) do
    # Validation is disabled - always return success
    {:ok, typescript_code}
  end
end
