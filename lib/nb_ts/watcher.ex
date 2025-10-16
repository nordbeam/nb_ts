defmodule NbTs.Watcher do
  @moduledoc """
  File watcher that automatically recompiles changed modules and triggers
  TypeScript type regeneration during development.

  This watcher monitors Elixir source files and recompiles only the specific
  files that change, triggering the @after_compile hooks which regenerate
  TypeScript types incrementally.

  ## How it works

  1. FileSystem monitors the lib/ directory for changes
  2. When a .ex file is modified, it's debounced for 200ms
  3. The specific file is recompiled using Code.compile_file/1
  4. @after_compile hooks fire for that module
  5. TypeScript types regenerate automatically if it's a serializer/controller

  ## Configuration

      # config/dev.exs
      config :nb_ts,
        output_dir: "assets/js/types",
        auto_generate: true,  # Enable compile hooks (default: true in dev)
        watch: true           # Enable file watcher (default: true in dev)

  Set `watch: false` to disable the file watcher while keeping other features.

  ## When it runs

  - Only in :dev environment
  - Only when auto_generate is enabled
  - Only when watch is enabled (default: true)
  - Automatically started by NbTs.Application
  """

  use GenServer
  require Logger

  @debounce_ms 200

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    watch_dirs = opts[:watch_dirs] || ["lib"]
    
    # Start FileSystem watcher
    {:ok, watcher_pid} = FileSystem.start_link(dirs: watch_dirs)
    FileSystem.subscribe(watcher_pid)
    
    Logger.debug("NbTs.Watcher started, watching: #{inspect(watch_dirs)}")
    
    {:ok, %{
      watcher: watcher_pid,
      timers: %{}  # path => timer_ref
    }}
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, events}}, state) do
    # Only handle .ex files that were modified
    if Path.extname(path) == ".ex" and (:modified in events or :created in events) do
      state = debounced_recompile(path, state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:recompile, path}, state) do
    recompile_file(path)
    
    # Remove timer from state
    state = %{state | timers: Map.delete(state.timers, path)}
    {:noreply, state}
  end

  # Debounce rapid file changes
  defp debounced_recompile(path, state) do
    # Cancel existing timer for this path
    case Map.get(state.timers, path) do
      nil -> :ok
      timer_ref -> Process.cancel_timer(timer_ref)
    end
    
    # Schedule new recompilation
    timer_ref = Process.send_after(self(), {:recompile, path}, @debounce_ms)
    
    %{state | timers: Map.put(state.timers, path, timer_ref)}
  end

  # Recompile a single file
  defp recompile_file(path) do
    try do
      # Check if file still exists (might have been deleted)
      if File.exists?(path) do
        # Recompile only this specific file
        case Code.compile_file(path) do
          modules when is_list(modules) ->
            module_names = Enum.map(modules, fn {mod, _bytecode} -> inspect(mod) end)
            Logger.debug("Recompiled: #{Path.relative_to_cwd(path)} (#{Enum.join(module_names, ", ")})")
            
          _ ->
            :ok
        end
      end
    rescue
      error ->
        Logger.warning("Failed to recompile #{path}: #{inspect(error)}")
    end
  end
end
