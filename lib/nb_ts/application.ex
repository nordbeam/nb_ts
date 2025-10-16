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
      ] ++ watcher_child()

    opts = [strategy: :one_for_one, name: NbTs.Supervisor]
    Supervisor.start_link(children, opts)
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
end
