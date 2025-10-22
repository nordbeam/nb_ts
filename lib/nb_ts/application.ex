defmodule NbTs.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # Registry for tracking serializers
        {NbTs.Registry, []},
        # Dependency tracker for managing notebook dependencies
        {NbTs.DependencyTracker, []}
      ] ++ tsgo_pool_child() ++ watcher_child()

    opts = [strategy: :one_for_one, name: NbTs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Only start TsgoPool in dev/test - validation is compile-time only
  # Also check if binary exists to avoid startup errors before download
  defp tsgo_pool_child do
    if Mix.env() in [:dev, :test] and tsgo_binary_exists?() do
      [{NbTs.TsgoPool, pool_size: pool_size()}]
    else
      []
    end
  end

  defp tsgo_binary_exists? do
    platform = detect_platform()
    binary_name = "tsgo-#{platform}#{if platform =~ "windows", do: ".exe", else: ""}"

    try do
      priv_dir = :code.priv_dir(:nb_ts)
      binary_path = Path.join([to_string(priv_dir), "tsgo", binary_name])
      File.exists?(binary_path)
    rescue
      _ -> false
    end
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

  # Conditionally add watcher based on environment and config
  defp watcher_child do
    if auto_watch_enabled?() do
      [{NbTs.Watcher, watch_dirs: ["lib"]}]
    else
      []
    end
  end

  defp auto_watch_enabled? do
    Mix.env() == :dev and
      Application.get_env(:nb_ts, :auto_generate, true) and
      Application.get_env(:nb_ts, :watch, true)
  end

  defp pool_size do
    # Default: max of schedulers or 10
    default = max(System.schedulers_online(), 10)
    Application.get_env(:nb_ts, :tsgo_pool_size, default)
  end
end
