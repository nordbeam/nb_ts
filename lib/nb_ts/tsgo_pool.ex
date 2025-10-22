defmodule NbTs.TsgoPool do
  @moduledoc """
  NimblePool for managing tsgo Port processes.

  Provides a pool of tsgo binary processes for efficient TypeScript validation
  with concurrency control and resource management.

  ## Pool Sizing

  Default pool size is 10, which allows 10 concurrent validations.
  Configure via:

      config :nb_ts, tsgo_pool_size: 20

  Recommended: `max(System.schedulers_online(), 10)`

  ## Architecture

  Each pool worker maintains a dedicated temp file that is reused for all validations
  by that worker. This eliminates file creation/deletion overhead. Each validation
  spawns a fresh tsgo process to avoid state pollution between validations.
  """

  @behaviour NimblePool

  require Logger

  @default_pool_size 10
  @default_timeout 30_000

  ## Public API

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Starts the tsgo pool.

  ## Options

    * `:pool_size` - Number of workers (default: 10)
    * `:name` - Pool name (default: __MODULE__)
  """
  def start_link(opts \\ []) do
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
    name = Keyword.get(opts, :name, __MODULE__)

    # Verify tsgo binary exists
    _ = tsgo_binary_path!()

    NimblePool.start_link(
      worker: {__MODULE__, opts},
      pool_size: pool_size,
      name: name
    )
  end

  @doc """
  Validates TypeScript code using a pooled tsgo process.

  ## Options

    * `:timeout` - Validation timeout in milliseconds (default: 30_000)
    * `:pool` - Pool name (default: __MODULE__)

  ## Examples

      iex> NbTs.TsgoPool.validate("const x: number = 5")
      {:ok, "const x: number = 5"}

      iex> NbTs.TsgoPool.validate("const x: number = 'bad'")
      {:error, "Type 'string' is not assignable to type 'number'"}
  """
  @spec validate(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def validate(typescript_code, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    pool = Keyword.get(opts, :pool, __MODULE__)
    # Extra time for pool operations
    pool_timeout = timeout + 1_000

    NimblePool.checkout!(
      pool,
      :checkout,
      fn _from, worker_state ->
        result = run_validation(worker_state, typescript_code, timeout)
        {result, worker_state}
      end,
      pool_timeout
    )
  rescue
    error ->
      Logger.error("tsgo validation error: #{inspect(error)}")
      {:error, "Validation failed: #{Exception.message(error)}"}
  end

  ## NimblePool Callbacks

  @impl NimblePool
  def init_worker(pool_state) do
    # Get and verify tsgo binary path
    tsgo_binary = tsgo_binary_path!()

    # Create dedicated temp file for this worker (reused for all validations)
    temp_file =
      Path.join(
        System.tmp_dir!(),
        "nb_ts_worker_#{:erlang.unique_integer([:positive])}.ts"
      )

    worker_state = %{
      binary: tsgo_binary,
      platform: detect_platform(),
      temp_file: temp_file
    }

    {:ok, worker_state, pool_state}
  end

  @impl NimblePool
  def handle_checkout(:checkout, _from, worker_state, pool_state) do
    # Worker state contains binary path
    # Client will open port for each validation
    {:ok, worker_state, worker_state, pool_state}
  end

  @impl NimblePool
  def handle_checkin(_status, _from, worker_state, pool_state) do
    # No cleanup needed - port is closed after each use
    {:ok, worker_state, pool_state}
  end

  @impl NimblePool
  def terminate_worker(_reason, worker_state, pool_state) do
    # Clean up temp file when worker terminates
    if File.exists?(worker_state.temp_file) do
      File.rm(worker_state.temp_file)
    end

    {:ok, pool_state}
  end

  ## Private Functions

  defp run_validation(worker_state, typescript_code, timeout) do
    # Reuse worker's dedicated temp file (no creation/deletion overhead)
    wrapped = wrap_code_if_needed(typescript_code)
    File.write!(worker_state.temp_file, wrapped)

    try do
      # Spawn tsgo process for this validation
      port =
        Port.open(
          {:spawn_executable, worker_state.binary},
          [
            {:args, ["--noEmit", worker_state.temp_file]},
            :binary,
            :use_stdio,
            :stderr_to_stdout,
            :exit_status
          ]
        )

      # Collect output
      case collect_output(port, <<>>, timeout) do
        {:ok, _output, 0} ->
          {:ok, typescript_code}

        {:ok, output, _exit_code} ->
          {:error, parse_diagnostics(output)}

        {:error, reason} ->
          {:error, "tsgo execution failed: #{inspect(reason)}"}
      end
    rescue
      e ->
        Logger.error("Failed to run validation: #{inspect(e)}\n#{Exception.format_stacktrace()}")
        {:error, "Validation error: #{Exception.message(e)}"}
    end
  end

  defp collect_output(port, acc, timeout) do
    receive do
      {^port, {:data, data}} ->
        collect_output(port, <<acc::binary, data::binary>>, timeout)

      {^port, {:exit_status, status}} ->
        # Port is automatically closed when we receive exit_status
        {:ok, acc, status}
    after
      timeout ->
        Port.close(port)
        {:error, :timeout}
    end
  end

  defp wrap_code_if_needed(code) do
    trimmed = String.trim_leading(code)

    # Check if the code is already a complete statement/declaration
    # If it starts with these keywords, it's already valid TypeScript
    complete_statement? =
      String.starts_with?(trimmed, [
        "export ",
        "type ",
        "interface ",
        "declare ",
        "import ",
        "const ",
        "let ",
        "var ",
        "function ",
        "class ",
        "enum ",
        "namespace ",
        "module "
      ])

    if complete_statement? do
      code
    else
      # Bare type expression - wrap it in a type alias
      "type __NbTsValidationType = #{code};"
    end
  end

  defp parse_diagnostics(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reject(&(&1 == ""))
    # Filter wrapper
    |> Enum.reject(&String.contains?(&1, "__NbTsValidationType"))
    |> Enum.map(&String.trim/1)
    # First 10 error lines
    |> Enum.take(10)
    |> Enum.join("\n")
  end

  defp tsgo_binary_path! do
    platform = detect_platform()
    binary_name = "tsgo-#{platform}#{if platform =~ "windows", do: ".exe", else: ""}"

    priv_dir = :code.priv_dir(:nb_ts)
    binary_path = Path.join([to_string(priv_dir), "tsgo", binary_name])

    unless File.exists?(binary_path) do
      raise """
      tsgo binary not found at: #{binary_path}

      Platform detected: #{platform}

      Run: mix nb_ts.download_tsgo
      """
    end

    binary_path
  end

  defp detect_platform do
    os = :os.type()
    arch = :erlang.system_info(:system_architecture) |> to_string()

    case os do
      {:unix, :darwin} ->
        if arch =~ ~r/aarch64|arm/i, do: "darwin-arm64", else: "darwin-amd64"

      {:unix, :linux} ->
        if arch =~ ~r/aarch64|arm/i, do: "linux-arm64", else: "linux-amd64"

      {:win32, _} ->
        if arch =~ ~r/aarch64|arm/i, do: "windows-arm64", else: "windows-amd64"
    end
  end
end
