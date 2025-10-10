defmodule NbTs.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for tracking serializers
      {NbTs.Registry, []}
    ]

    opts = [strategy: :one_for_one, name: NbTs.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
