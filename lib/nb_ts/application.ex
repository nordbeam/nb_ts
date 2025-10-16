defmodule NbTs.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for tracking serializers
      {NbTs.Registry, []},
      # Dependency tracker for managing notebook dependencies
      {NbTs.DependencyTracker, []}
    ]

    opts = [strategy: :one_for_one, name: NbTs.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
