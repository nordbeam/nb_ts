defmodule NbTs.Watcher do
  @moduledoc """
  FileSystem-based watcher for automatic TypeScript type generation.

  This GenServer watches for changes in Elixir files and automatically
  regenerates TypeScript types when serializers or Inertia pages are modified.

  ## Usage

  Add to your application's supervision tree in `lib/my_app/application.ex`:

      def start(_type, _args) do
        children = [
          # ... other children
          {NbTs.Watcher, output_dir: "assets/js/types"}
        ]

        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

  Or configure it to only run in development:

      defp children(:dev) do
        [
          {NbTs.Watcher, output_dir: "assets/js/types"}
        ]
      end

      defp children(_), do: []

      def start(_type, _args) do
        children = [
          # ... other children
        ] ++ children(Mix.env())

        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end
  """

  use GenServer
  require Logger

  @default_output_dir "assets/js/types"
  @debounce_delay 500

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    output_dir = Keyword.get(opts, :output_dir, @default_output_dir)
    dirs = ["lib"]

    {:ok, watcher_pid} = FileSystem.start_link(dirs: dirs)
    FileSystem.subscribe(watcher_pid)

    Logger.info("NbTs file watcher started, watching: #{inspect(dirs)}")

    {:ok, %{watcher_pid: watcher_pid, debounce_ref: nil, output_dir: output_dir}}
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, _events}}, state) do
    # Only regenerate for .ex files
    if Path.extname(path) == ".ex" do
      # Cancel previous debounce timer if exists
      if state.debounce_ref do
        Process.cancel_timer(state.debounce_ref)
      end

      # Debounce regeneration to avoid multiple runs
      ref = Process.send_after(self(), :regenerate_types, @debounce_delay)
      {:noreply, %{state | debounce_ref: ref}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    Logger.info("NbTs file watcher stopped")
    {:noreply, state}
  end

  @impl true
  def handle_info(:regenerate_types, state) do
    Logger.info("Regenerating TypeScript types...")

    case NbTs.Generator.generate(output_dir: state.output_dir) do
      {:ok, results} ->
        Logger.info(
          "TypeScript types regenerated successfully (#{results.total_files} files in #{results.output_dir})"
        )

      {:error, reason} ->
        Logger.warning("Failed to regenerate TypeScript types: #{inspect(reason)}")
    end

    {:noreply, %{state | debounce_ref: nil}}
  end
end
