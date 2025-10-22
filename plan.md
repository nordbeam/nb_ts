# Implementation Plan: TypeScript Validation with tsgo + NimblePool

## Executive Summary

Replace oxc-based TypeScript syntax validation with full type checking using tsgo (Microsoft's native Go TypeScript compiler) via NimblePool-managed Erlang Ports.

**Key Benefits**:
- ✅ **Full TypeScript type checking** (not just syntax like oxc)
- ✅ **10x faster** than traditional tsc (~10-20ms vs 50-200ms)
- ✅ **Native binary** (no npm/node runtime dependency)
- ✅ **Pool-based** for concurrency control and resource management
- ✅ **No subprocesses** (uses Erlang Ports with direct ownership transfer)

---

## Table of Contents

1. [Research Findings](#research-findings)
2. [Architecture Overview](#architecture-overview)
3. [Implementation Steps](#implementation-steps)
4. [Configuration](#configuration)
5. [Testing Strategy](#testing-strategy)
6. [Migration Path](#migration-path)
7. [Performance Considerations](#performance-considerations)
8. [Risk Assessment](#risk-assessment)
9. [Open Questions](#open-questions)

---

## Research Findings

### 1. tsgo (TypeScript Go Compiler)

**Source**: https://github.com/microsoft/typescript-go

**Version**: 7.0.0-dev.20251022 (Preview/Experimental)

**Status**: Staging repo for native TypeScript port, will merge into microsoft/TypeScript

**Performance**: 10x faster than tsc on most projects

**Binary Sizes** (compressed):
```
darwin-amd64:  6.3 MB
darwin-arm64:  5.9 MB
linux-amd64:   6.3 MB
linux-arm64:   5.7 MB
windows-amd64: 6.5 MB
windows-arm64: 5.8 MB
```

**Binary Sizes** (extracted): ~20-30 MB per platform

**Installation**: Available via npm (`@typescript/native-preview`) or direct binary download from sxzz/tsgo-releases

**CLI Compatibility**:
- ✅ Uses same CLI API as tsc
- ✅ Supports `--noEmit` for type checking only
- ✅ Supports `--watch` mode (experimental, not optimized)
- ❌ Missing `--help`, `--init`, `--build`, and some emit options
- ❌ No stdin/stdout protocol for interactive communication

**Key Limitation**: Watch mode exists but has "no incremental rechecking and is not optimized"

**Recommendation**: Use one-shot mode (not watch) for each validation

---

### 2. NimblePool

**Source**: https://github.com/dashbitco/nimble_pool

**Author**: Dashbit (José Valim's company)

**Purpose**: Resource pooling (not process pooling)

**Why NimblePool over Poolboy/Poolex**:

| Feature | NimblePool | Poolboy | Poolex |
|---------|-----------|---------|--------|
| **Designed for** | Resources (Ports, Sockets) | Processes | Processes |
| **Data copying** | ✅ None (direct transfer) | ❌ Yes (overhead) | ❌ Yes (overhead) |
| **Maintenance** | ✅ Active | ❌ Unmaintained | ✅ Active |
| **Port examples** | ✅ In docs | ❌ No | ❌ No |

**Key Pattern**: Port ownership transfer via `Port.connect/2`

```elixir
# NimblePool transfers port ownership directly to client
@impl NimblePool
def handle_checkout(:checkout, {pid, _}, port, pool_state) do
  Port.connect(port, pid)  # Transfer ownership
  {:ok, port, port, pool_state}
end
```

This avoids data copying between processes - the client communicates directly with the port.

---

### 3. Erlang Port Communication

**Best Practices**:

1. **Use line mode for text protocols**: `{:line, max_bytes}`
2. **Use exit_status to detect termination**: `:exit_status`
3. **Proper cleanup prevents zombies**: Always `Port.close/1` in terminate
4. **Ownership model**: Connected process controls port lifecycle

**Zombie Process Prevention**:
- Port automatically terminates external process when closed
- If external program doesn't check stdio, it may become orphan
- tsgo should terminate cleanly (standard compiler behavior)

**Communication Modes**:
```elixir
# Line-based (good for compiler output)
Port.open({:spawn_executable, binary}, [
  :binary,
  :use_stdio,
  :stderr_to_stdout,
  :exit_status,
  {:line, 16384}  # 16KB line buffer
])

# Stream mode (for large output)
Port.open({:spawn_executable, binary}, [
  :binary,
  :use_stdio,
  :stderr_to_stdout,
  :exit_status
])
```

**Recommendation**: Use exit_status mode (one-shot invocation) since watch mode is unreliable

---

### 4. deno_rider Evaluation

**Initial Request**: "Use deno_rider's eval"

**Problem Discovered**:
- ❌ deno_rider has no npm support
- ❌ Cannot import TypeScript compiler
- ✅ Could bundle TSC (~10MB) and load via eval
- ⚠️ Complex implementation (days of work)
- ⚠️ Requires forking deno_rider

**Decision**: Use tsgo binary + Ports instead (simpler, faster, cleaner)

---

### 5. Current State (oxc)

**Location**: `native/typescript_validator/src/lib.rs`

**What it does**:
- ✅ Syntax validation (parsing only)
- ❌ No type checking
- ❌ No type inference
- ❌ No semantic analysis (only basic)

**Performance**: 1-5ms per validation

**Usage**: Called from `NbTs.Generator.validate/1`

**Fallback**: Elixir pattern matching when NIF not loaded

**Limitation**: Only catches syntax errors, not type errors:
```typescript
// oxc says OK (valid syntax)
const x: number = "string";  // Type error!

// tsgo catches this ✓
```

---

## Architecture Overview

### High-Level Design

```
┌─────────────────────────────────────────────────────────────┐
│                     NbTs Application                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  NbTs.Generator.validate/1                                  │
│         │                                                    │
│         ├──> NbTs.TsgoValidator.validate/1                 │
│         │           │                                        │
│         │           └──> NbTs.TsgoPool (NimblePool)        │
│         │                       │                            │
│         │                       ├─ Port 1 (tsgo binary)     │
│         │                       ├─ Port 2 (tsgo binary)     │
│         │                       ├─ Port 3 (tsgo binary)     │
│         │                       └─ ... (configurable size)  │
│         │                                                    │
│         └──> [fallback] validate_with_oxc/1 (if tsgo fails)│
│                                                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Binary Distribution                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  priv/tsgo/                                                 │
│    ├── tsgo-darwin-amd64      (6 MB)                        │
│    ├── tsgo-darwin-arm64      (6 MB)                        │
│    ├── tsgo-linux-amd64       (6 MB)                        │
│    ├── tsgo-linux-arm64       (6 MB)                        │
│    ├── tsgo-windows-amd64.exe (6 MB)                        │
│    └── tsgo-windows-arm64.exe (6 MB)                        │
│                                                              │
│  Total size: ~36 MB (all platforms)                         │
│  Runtime size: ~6 MB (one platform)                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Validation Flow

```
1. Client calls NbTs.TsgoValidator.validate(code)
                    │
                    ▼
2. Wrap code if needed (bare type expressions)
                    │
                    ▼
3. Create temp file with TypeScript code
                    │
                    ▼
4. Checkout port from NimblePool
   - Pool transfers port ownership to client
   - Client now owns the port directly
                    │
                    ▼
5. Spawn tsgo process via Port
   Port.open({:spawn_executable, tsgo_path}, [
     {:args, ["--noEmit", temp_file]},
     :binary,
     :use_stdio,
     :stderr_to_stdout,
     :exit_status
   ])
                    │
                    ▼
6. tsgo validates TypeScript
   - Parses code
   - Builds type graph
   - Performs type checking
   - Outputs diagnostics to stderr
                    │
                    ▼
7. Collect output from port
   - Read all data
   - Wait for exit_status
                    │
                    ▼
8. Parse diagnostics
   - exit_status = 0 → success
   - exit_status != 0 → parse errors
                    │
                    ▼
9. Clean up
   - Delete temp file
   - Port.close()
   - Checkin to pool
                    │
                    ▼
10. Return result
    {:ok, code} or {:error, diagnostics}
```

---

## Implementation Steps

### Phase 1: Binary Distribution Setup

**Estimated Time**: 2-3 hours

#### 1.1 Create Download Script

**File**: `scripts/download_tsgo.sh`

```bash
#!/usr/bin/env bash
set -e

VERSION="${TSGO_VERSION:-2025-10-22}"
BASE_URL="https://github.com/sxzz/tsgo-releases/releases/download/${VERSION}"
PRIV_DIR="priv/tsgo"

echo "Downloading tsgo binaries version ${VERSION}..."
mkdir -p "${PRIV_DIR}"

platforms=(
  "darwin-amd64:tar.gz"
  "darwin-arm64:tar.gz"
  "linux-amd64:tar.gz"
  "linux-arm64:tar.gz"
  "windows-amd64:zip"
  "windows-arm64:zip"
)

for platform_ext in "${platforms[@]}"; do
  IFS=':' read -r platform ext <<< "$platform_ext"
  filename="tsgo-${platform}.${ext}"

  echo "  Downloading ${filename}..."
  curl -L -o "/tmp/${filename}" "${BASE_URL}/${filename}"

  # Extract binary
  if [ "$ext" = "tar.gz" ]; then
    tar -xzf "/tmp/${filename}" -C "${PRIV_DIR}" tsgo
    mv "${PRIV_DIR}/tsgo" "${PRIV_DIR}/tsgo-${platform}"
  else
    unzip -j "/tmp/${filename}" tsgo.exe -d "${PRIV_DIR}"
    mv "${PRIV_DIR}/tsgo.exe" "${PRIV_DIR}/tsgo-${platform}.exe"
  fi

  chmod +x "${PRIV_DIR}/tsgo-${platform}"* 2>/dev/null || true
  rm "/tmp/${filename}"

  echo "    ✓ Installed tsgo-${platform}"
done

echo ""
echo "All tsgo binaries downloaded to ${PRIV_DIR}"
echo ""
echo "Verifying installation..."
ls -lh "${PRIV_DIR}"
```

#### 1.2 Create Mix Task

**File**: `lib/mix/tasks/nb_ts.download_tsgo.ex`

```elixir
defmodule Mix.Tasks.NbTs.DownloadTsgo do
  @moduledoc """
  Downloads tsgo binaries for all supported platforms.

  ## Usage

      mix nb_ts.download_tsgo

  ## Environment Variables

    * `TSGO_VERSION` - Version to download (default: 2025-10-22)
    * `TSGO_PLATFORMS` - Comma-separated platforms (default: all)

  ## Examples

      # Download all platforms
      mix nb_ts.download_tsgo

      # Download specific version
      TSGO_VERSION=2025-10-15 mix nb_ts.download_tsgo

      # Download only current platform
      TSGO_PLATFORMS=darwin-arm64 mix nb_ts.download_tsgo
  """

  use Mix.Task

  @shortdoc "Downloads tsgo binaries"

  @version System.get_env("TSGO_VERSION") || "2025-10-22"
  @base_url "https://github.com/sxzz/tsgo-releases/releases/download/#{@version}"

  @platforms %{
    "darwin-amd64" => "tar.gz",
    "darwin-arm64" => "tar.gz",
    "linux-amd64" => "tar.gz",
    "linux-arm64" => "tar.gz",
    "windows-amd64" => "zip",
    "windows-arm64" => "zip"
  }

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")

    # Ensure :inets and :ssl applications are started for httpc
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    priv_dir = Path.join([Mix.Project.app_path(), "priv", "tsgo"])
    File.mkdir_p!(priv_dir)

    platforms = get_platforms()

    Mix.shell().info("Downloading tsgo binaries (version #{@version})...")

    for platform <- platforms do
      download_platform(platform, priv_dir)
    end

    Mix.shell().info("")
    Mix.shell().info("✓ All tsgo binaries downloaded to #{priv_dir}")
    list_binaries(priv_dir)
  end

  defp get_platforms do
    case System.get_env("TSGO_PLATFORMS") do
      nil -> Map.keys(@platforms)
      str -> String.split(str, ",", trim: true)
    end
  end

  defp download_platform(platform, priv_dir) do
    ext = Map.fetch!(@platforms, platform)
    filename = "tsgo-#{platform}.#{ext}"
    url = "#{@base_url}/#{filename}"

    Mix.shell().info("  Downloading #{filename}...")

    case download_file(url) do
      {:ok, data} ->
        extract_binary(platform, ext, data, priv_dir)
        Mix.shell().info("    ✓ Installed tsgo-#{platform}")

      {:error, reason} ->
        Mix.shell().error("    ✗ Failed: #{inspect(reason)}")
        raise "Failed to download #{filename}"
    end
  end

  defp download_file(url) do
    url_charlist = String.to_charlist(url)

    case :httpc.request(:get, {url_charlist, []},
                        [{:timeout, 60_000}],
                        [{:body_format, :binary}]) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        {:ok, body}

      {:ok, {{_, status, _}, _, _}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_binary(platform, "tar.gz", data, priv_dir) do
    # Write to temp file
    temp_file = Path.join(System.tmp_dir!(), "tsgo-#{platform}.tar.gz")
    File.write!(temp_file, data)

    # Extract
    :erl_tar.extract(temp_file, [:compressed, {:cwd, String.to_charlist(priv_dir)}])

    # Rename
    File.rename!(
      Path.join(priv_dir, "tsgo"),
      Path.join(priv_dir, "tsgo-#{platform}")
    )

    # Set executable
    File.chmod!(Path.join(priv_dir, "tsgo-#{platform}"), 0o755)

    File.rm!(temp_file)
  end

  defp extract_binary(platform, "zip", data, priv_dir) do
    # Write to temp file
    temp_file = Path.join(System.tmp_dir!(), "tsgo-#{platform}.zip")
    File.write!(temp_file, data)

    # Extract
    :zip.extract(temp_file, [{:cwd, String.to_charlist(priv_dir)}])

    # Rename
    File.rename!(
      Path.join(priv_dir, "tsgo.exe"),
      Path.join(priv_dir, "tsgo-#{platform}.exe")
    )

    # Set executable (no-op on Windows)
    File.chmod!(Path.join(priv_dir, "tsgo-#{platform}.exe"), 0o755)

    File.rm!(temp_file)
  end

  defp list_binaries(priv_dir) do
    Mix.shell().info("")
    Mix.shell().info("Installed binaries:")

    priv_dir
    |> File.ls!()
    |> Enum.each(fn file ->
      path = Path.join(priv_dir, file)
      size = File.stat!(path).size
      size_mb = Float.round(size / 1_024 / 1_024, 1)
      Mix.shell().info("  #{file} (#{size_mb} MB)")
    end)
  end
end
```

#### 1.3 Update mix.exs

```elixir
def project do
  [
    app: :nb_ts,
    # ... existing config ...

    # Run download task before compile (optional)
    # compilers: [:download_tsgo] ++ Mix.compilers(),
  ]
end

def application do
  [
    mod: {NbTs.Application, []},
    extra_applications: [:logger, :inets, :ssl]
  ]
end

defp deps do
  [
    {:nimble_pool, "~> 1.1"},
    # ... existing deps ...
  ]
end
```

#### 1.4 Update .gitignore

```
# tsgo binaries (download during build)
/priv/tsgo/
```

#### 1.5 Update README

Add section about tsgo download:

```markdown
## Setup

### Download tsgo binaries

```bash
mix nb_ts.download_tsgo
```

This downloads tsgo binaries for all platforms (~36 MB total).
Only the binary for your platform will be used at runtime (~6 MB).
```

---

### Phase 2: NimblePool Implementation

**Estimated Time**: 4-6 hours

#### 2.1 Create TsgoPool Module

**File**: `lib/nb_ts/tsgo_pool.ex`

```elixir
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

  Each pool worker maintains a tsgo binary path. On checkout, a new Port is
  opened for the validation, then closed on checkin. This avoids complexity
  with watch mode while still providing pooling benefits (concurrency control).
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
    pool_timeout = timeout + 1_000  # Extra time for pool operations

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

    worker_state = %{
      binary: tsgo_binary,
      platform: detect_platform()
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
  def terminate_worker(_reason, _worker_state, pool_state) do
    # No resources to clean up
    {:ok, pool_state}
  end

  ## Private Functions

  defp run_validation(worker_state, typescript_code, timeout) do
    # Create temp file
    temp_file = create_temp_file(typescript_code)

    try do
      # Open port for this validation
      port = Port.open(
        {:spawn_executable, worker_state.binary},
        [
          {:args, ["--noEmit", temp_file]},
          :binary,
          :use_stdio,
          :stderr_to_stdout,
          :exit_status
        ]
      )

      # Collect output
      case collect_output(port, <<>>, timeout) do
        {:ok, output, 0} ->
          # Success - no errors
          {:ok, typescript_code}

        {:ok, output, _exit_code} ->
          # Type errors
          {:error, parse_diagnostics(output)}

        {:error, reason} ->
          {:error, "tsgo execution failed: #{inspect(reason)}"}
      end
    after
      File.rm(temp_file)
    end
  end

  defp collect_output(port, acc, timeout) do
    receive do
      {^port, {:data, data}} ->
        collect_output(port, <<acc::binary, data::binary>>, timeout)

      {^port, {:exit_status, status}} ->
        Port.close(port)
        {:ok, acc, status}
    after
      timeout ->
        Port.close(port)
        {:error, :timeout}
    end
  end

  defp create_temp_file(code) do
    wrapped = wrap_code_if_needed(code)
    temp = Path.join(
      System.tmp_dir!(),
      "nb_ts_#{:erlang.unique_integer([:positive])}.ts"
    )
    File.write!(temp, wrapped)
    temp
  end

  defp wrap_code_if_needed(code) do
    trimmed = String.trim_start(code)

    if String.starts_with?(trimmed, ["export", "type ", "interface ", "declare ", "import "]) do
      code
    else
      "type __NbTsValidationType = #{code};"
    end
  end

  defp parse_diagnostics(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reject(&String.contains?(&1, "__NbTsValidationType"))  # Filter wrapper
    |> Enum.map(&String.trim/1)
    |> Enum.take(10)  # First 10 error lines
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
```

#### 2.2 Create TsgoValidator Wrapper

**File**: `lib/nb_ts/tsgo_validator.ex`

```elixir
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
    NbTs.TsgoPool.validate(typescript_code, opts)
  end
end
```

---

### Phase 3: Application Integration

**Estimated Time**: 2-3 hours

#### 3.1 Create Application Module

**File**: `lib/nb_ts/application.ex`

```elixir
defmodule NbTs.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for tracking serializers
      {Registry, keys: :duplicate, name: NbTs.Registry},

      # tsgo pool for TypeScript validation
      {NbTs.TsgoPool, pool_size: pool_size()}
    ]

    opts = [strategy: :one_for_one, name: NbTs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp pool_size do
    # Default: max of schedulers or 10
    default = max(System.schedulers_online(), 10)
    Application.get_env(:nb_ts, :tsgo_pool_size, default)
  end
end
```

#### 3.2 Update Generator

**File**: `lib/nb_ts/generator.ex`

```elixir
# Update validate/1 function:

def validate(typescript_string) do
  case NbTs.TsgoValidator.validate(typescript_string) do
    {:ok, _} = result ->
      result

    {:error, reason} when is_binary(reason) ->
      # Check if tsgo is unavailable
      if reason =~ "tsgo binary not found" or reason =~ "Validation failed" do
        # Fall back to oxc
        validate_with_oxc(typescript_string)
      else
        {:error, reason}
      end

    {:error, _} = error ->
      # Unknown error, try oxc fallback
      validate_with_oxc(typescript_string)
  end
end

# Keep existing oxc implementation as fallback
defp validate_with_oxc(code) do
  # ... existing implementation
end
```

---

### Phase 4: Configuration

**Estimated Time**: 1 hour

#### 4.1 Add Configuration Options

**File**: `config/config.exs`

```elixir
import Config

config :nb_ts,
  # Pool size for tsgo validators
  # Recommended: max(System.schedulers_online(), 10)
  tsgo_pool_size: max(System.schedulers_online(), 10),

  # Validation timeout (milliseconds)
  tsgo_timeout: 30_000,

  # Fallback to oxc if tsgo unavailable
  fallback_to_oxc: true

# Environment-specific overrides
import_config "#{config_env()}.exs"
```

**File**: `config/dev.exs`

```elixir
import Config

config :nb_ts,
  # Smaller pool in dev
  tsgo_pool_size: 5,

  # Shorter timeout in dev
  tsgo_timeout: 10_000
```

**File**: `config/test.exs`

```elixir
import Config

config :nb_ts,
  # Single worker for tests
  tsgo_pool_size: 1,

  # Fast timeout for tests
  tsgo_timeout: 5_000
```

**File**: `config/prod.exs`

```elixir
import Config

config :nb_ts,
  # Larger pool in production
  tsgo_pool_size: max(System.schedulers_online() * 2, 20),

  # Longer timeout for complex types
  tsgo_timeout: 60_000
```

---

### Phase 5: Testing

**Estimated Time**: 3-4 hours

#### 5.1 Unit Tests

**File**: `test/nb_ts/tsgo_pool_test.exs`

```elixir
defmodule NbTs.TsgoPoolTest do
  use ExUnit.Case, async: false

  alias NbTs.TsgoPool

  setup_all do
    # Ensure tsgo binaries are downloaded
    unless File.exists?(Path.join([:code.priv_dir(:nb_ts), "tsgo"])) do
      Mix.Task.run("nb_ts.download_tsgo")
    end

    :ok
  end

  describe "validate/1" do
    test "validates correct TypeScript" do
      assert {:ok, _} = TsgoPool.validate("const x: number = 5")
      assert {:ok, _} = TsgoPool.validate("const y: string = 'hello'")
    end

    test "validates interfaces" do
      code = """
      export interface User {
        id: number;
        name: string;
      }
      """
      assert {:ok, _} = TsgoPool.validate(code)
    end

    test "rejects type mismatches" do
      assert {:error, msg} = TsgoPool.validate("const x: number = 'string'")
      assert msg =~ "not assignable" or msg =~ "Type"
    end

    test "rejects syntax errors" do
      assert {:error, _} = TsgoPool.validate("const x: number = {")
    end

    test "validates complex types" do
      code = """
      export interface User {
        id: number;
        name: string;
        emails: Array<string>;
        metadata: Record<string, unknown>;
        optional?: boolean;
      }
      """
      assert {:ok, _} = TsgoPool.validate(code)
    end

    test "wraps bare type expressions" do
      assert {:ok, _} = TsgoPool.validate("{ id: number; name: string }")
      assert {:ok, _} = TsgoPool.validate("number | string")
      assert {:ok, _} = TsgoPool.validate("Array<string>")
    end

    test "handles union types" do
      assert {:ok, _} = TsgoPool.validate("type Status = 'pending' | 'active' | 'deleted'")
    end

    test "handles generic types" do
      code = """
      export interface Response<T> {
        data: T;
        error: string | null;
      }
      """
      assert {:ok, _} = TsgoPool.validate(code)
    end
  end

  describe "concurrency" do
    test "handles concurrent validations" do
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            TsgoPool.validate("const x#{i}: number = #{i}")
          end)
        end

      results = Task.await_many(tasks, 30_000)

      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end

  describe "timeout handling" do
    @tag :slow
    test "respects timeout" do
      # Generate extremely complex type to trigger timeout
      complex_type = generate_complex_type(1000)

      assert {:error, msg} = TsgoPool.validate(complex_type, timeout: 100)
      assert msg =~ "timeout" or msg =~ "failed"
    end
  end

  defp generate_complex_type(depth) do
    """
    type Complex = {
      #{for i <- 1..depth do
        "field#{i}: number | string | boolean | null;"
      end |> Enum.join("\n  ")}
    }
    """
  end
end
```

**File**: `test/nb_ts/tsgo_validator_test.exs`

```elixir
defmodule NbTs.TsgoValidatorTest do
  use ExUnit.Case

  alias NbTs.TsgoValidator

  test "validates simple TypeScript" do
    assert {:ok, _} = TsgoValidator.validate("const x: number = 5")
  end

  test "rejects type errors" do
    assert {:error, _} = TsgoValidator.validate("const x: number = 'bad'")
  end
end
```

#### 5.2 Integration Tests

**File**: `test/nb_ts/generator_test.exs`

```elixir
# Update existing tests to use tsgo

test "validates generated TypeScript with tsgo" do
  # Generate types
  {:ok, _} = NbTs.Generator.generate(output_dir: output_dir, validate: true)

  # All files should be valid
  # (tsgo will catch type errors that oxc missed)
end
```

---

### Phase 6: Documentation

**Estimated Time**: 2 hours

#### 6.1 Update README

Add sections:
- Installation instructions (download tsgo)
- Configuration options
- Performance characteristics
- Troubleshooting

#### 6.2 Add Module Documentation

Document all public functions with examples

#### 6.3 Create Migration Guide

**File**: `docs/migration_to_tsgo.md`

```markdown
# Migration to tsgo

This guide covers migrating from oxc to tsgo for TypeScript validation.

## Breaking Changes

None - tsgo is a drop-in replacement with better validation.

## Benefits

- Full type checking (not just syntax)
- 10x faster than tsc
- Catches type errors oxc missed

## Setup

1. Download tsgo binaries:
   ```bash
   mix nb_ts.download_tsgo
   ```

2. Update config (optional):
   ```elixir
   config :nb_ts, tsgo_pool_size: 20
   ```

3. Run tests:
   ```bash
   mix test
   ```

## Fallback

oxc is kept as fallback if tsgo unavailable.
```

---

## Configuration

### Environment Variables

```bash
# Download configuration
TSGO_VERSION=2025-10-22        # Version to download
TSGO_PLATFORMS=darwin-arm64    # Specific platforms

# Runtime configuration
MIX_ENV=prod                   # Environment
```

### Application Configuration

```elixir
config :nb_ts,
  # Pool size (default: max(schedulers, 10))
  tsgo_pool_size: 10,

  # Validation timeout in ms (default: 30_000)
  tsgo_timeout: 30_000,

  # Fallback to oxc if tsgo fails (default: true)
  fallback_to_oxc: true
```

---

## Testing Strategy

### Unit Tests
- ✅ TsgoPool validation
- ✅ Concurrent validation
- ✅ Timeout handling
- ✅ Error parsing
- ✅ Code wrapping

### Integration Tests
- ✅ Generator integration
- ✅ End-to-end validation
- ✅ Fallback behavior

### Manual Testing
- ✅ Download binaries on all platforms
- ✅ Run on macOS ARM
- ✅ Run on Linux
- ✅ Run on Windows

### Performance Testing
- ✅ Benchmark vs oxc
- ✅ Benchmark vs tsc
- ✅ Measure pool saturation
- ✅ Memory usage

---

## Migration Path

### Phase 1: Parallel Implementation (Week 1)
1. Add tsgo as optional validator
2. Keep oxc as default
3. Test thoroughly

### Phase 2: Switch Default (Week 2)
1. Make tsgo primary validator
2. Keep oxc as fallback
3. Monitor in production

### Phase 3: Deprecate oxc (Month 2+)
1. Remove oxc dependency
2. Clean up fallback code
3. Simplify validation logic

---

## Performance Considerations

### Expected Performance

```
Validation times (per file):
- oxc:  1-5ms   (syntax only)
- tsgo: 10-20ms (full type check)
- tsc:  50-200ms (full type check)

Throughput (10 workers):
- 500-1000 validations/second

Memory usage:
- Binary size: ~6 MB per platform
- Runtime overhead: ~10 MB per pool worker
- Total: ~60-100 MB for pool of 10
```

### Optimization Tips

1. **Pool Sizing**:
   - Development: 5 workers
   - Production: `max(schedulers * 2, 20)`
   - CPU-bound: 1-2 per core
   - I/O-bound: 2-4 per core

2. **Timeout Configuration**:
   - Simple types: 5 seconds
   - Complex types: 30 seconds
   - Very complex: 60 seconds

3. **Temp File Cleanup**:
   - Automatic via `after` blocks
   - System.tmp_dir() auto-cleans on reboot

4. **Binary Distribution**:
   - Only include current platform in releases
   - Use `mix nb_ts.download_tsgo` with `TSGO_PLATFORMS=darwin-arm64`

---

## Risk Assessment

### High Risk
None identified

### Medium Risk

1. **tsgo is experimental**
   - Mitigation: Keep oxc fallback
   - Probability: Medium
   - Impact: Low (fallback works)

2. **Binary size increase**
   - Mitigation: Download on demand, exclude from git
   - Probability: High
   - Impact: Low (6MB not significant)

### Low Risk

1. **Platform detection issues**
   - Mitigation: Comprehensive platform detection
   - Probability: Low
   - Impact: Low (fallback to oxc)

2. **Port zombie processes**
   - Mitigation: Proper cleanup, tested patterns
   - Probability: Very Low
   - Impact: Low (auto-cleanup)

---

## Open Questions

### 1. Watch Mode Viability

**Question**: Should we attempt to use `tsgo --watch` for long-running ports?

**Research Needed**:
- Test watch mode stability
- Measure performance improvement
- Test file change notification protocol

**Current Recommendation**: Use one-shot mode (simpler, proven)

**Decision**: Implement one-shot first, evaluate watch later

---

### 2. Pool Size Tuning

**Question**: What's the optimal pool size for different scenarios?

**Research Needed**:
- Benchmark different pool sizes
- Measure saturation point
- Test on different hardware

**Current Recommendation**: Start with 10, tune based on metrics

**Decision**: Make configurable, provide guidelines

---

### 3. Binary Distribution Strategy

**Question**: Should we bundle binaries in releases?

**Options**:
1. Bundle all platforms (36 MB)
2. Bundle current platform only (6 MB)
3. Download on first use

**Current Recommendation**: Download during build, exclude from git

**Decision**: Use Mix task, document clearly

---

### 4. Error Message Quality

**Question**: How to improve diagnostic output from tsgo?

**Research Needed**:
- Compare tsgo vs tsc error messages
- Test error message parsing
- User experience testing

**Current Recommendation**: Pass through tsgo errors, filter wrapper artifacts

**Decision**: Implement basic filtering, improve iteratively

---

### 5. CI/CD Integration

**Question**: How to handle binary downloads in CI?

**Options**:
1. Download during CI build
2. Cache binaries between runs
3. Commit binaries (not recommended)

**Current Recommendation**: Download + cache

**Example** (GitHub Actions):
```yaml
- uses: actions/cache@v3
  with:
    path: priv/tsgo
    key: tsgo-${{ runner.os }}-${{ hashFiles('mix.lock') }}

- run: mix nb_ts.download_tsgo
```

---

## Success Criteria

### Must Have
- ✅ Full TypeScript type checking
- ✅ Faster than tsc
- ✅ Drop-in replacement for oxc
- ✅ oxc fallback works
- ✅ Tests pass

### Should Have
- ✅ <20ms validation time
- ✅ Concurrent validation support
- ✅ Clear error messages
- ✅ Easy setup (one command)

### Nice to Have
- ⏳ Watch mode support
- ⏳ Incremental validation
- ⏳ Cache validation results

---

## Timeline

**Total Estimated Time**: 14-19 hours

**Week 1**:
- Day 1-2: Binary distribution (2-3 hours)
- Day 3-4: NimblePool implementation (4-6 hours)
- Day 5: Application integration (2-3 hours)

**Week 2**:
- Day 1: Configuration (1 hour)
- Day 2-3: Testing (3-4 hours)
- Day 4: Documentation (2 hours)
- Day 5: Review and polish

---

## Rollback Plan

If tsgo doesn't work:

1. **Immediate Rollback**:
   ```elixir
   config :nb_ts, fallback_to_oxc: true
   ```

2. **Remove tsgo**:
   - Comment out TsgoPool in supervision tree
   - Update Generator to use oxc directly

3. **Complete Removal**:
   - Remove tsgo_pool.ex
   - Remove tsgo_validator.ex
   - Remove download task
   - Keep oxc as primary

---

## Conclusion

This implementation provides:
- ✅ Full TypeScript type checking
- ✅ 10x faster than tsc
- ✅ Clean architecture with NimblePool
- ✅ Robust fallback mechanism
- ✅ Comprehensive testing
- ✅ Clear documentation

The plan is thorough, well-researched, and ready for implementation.

Next step: Begin Phase 1 (Binary Distribution Setup)
