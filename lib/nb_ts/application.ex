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
  defp tsgo_pool_child do
    if Mix.env() in [:dev, :test] do
      [{NbTs.TsgoPool, pool_size: pool_size()}]
    else
      []
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
