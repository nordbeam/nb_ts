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

    # If pool is not available (e.g., binary not downloaded yet), skip validation
    # This allows projects to compile before downloading the binary
    case Process.whereis(NbTs.TsgoPool) do
      nil ->
        # Pool not started - skip validation during compilation
        # Log warning if configured (default: quiet in test mode)
        if log_validation_warnings?() do
          require Logger

          Logger.warning("Skipping TypeScript validation - tsgo binary not available. Run: mix nb_ts.download_tsgo")
        end

        {:ok, typescript_code}

      _pid ->
        # Pool is available - perform validation
        NbTs.TsgoPool.validate(typescript_code, opts)
    end
  end

  # Checks if validation warnings should be logged
  # Defaults to false in test environment, true otherwise
  # Can be overridden via application config
  defp log_validation_warnings? do
    Application.get_env(:nb_ts, :log_validation_warnings, Mix.env() != :test)
  end
end
