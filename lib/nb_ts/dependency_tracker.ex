defmodule NbTs.DependencyTracker do
  @moduledoc """
  Tracks dependencies between TypeScript type files.

  Maintains a graph of which generated files depend on which modules,
  enabling cascade updates when a type changes.

  ## Dependency Types

  - Controller pages depend on:
    - Serializers used in prop types
    - SharedProps modules referenced via `inertia_shared`

  - Index file depends on:
    - All generated type files
  """

  use GenServer

  @table_name :nb_ts_dependencies

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record that a generated file depends on a module.

  ## Examples

      # UsersIndexProps.ts depends on MyApp.UserSerializer
      DependencyTracker.add_dependency("UsersIndexProps.ts", MyApp.UserSerializer)
  """
  def add_dependency(generated_file, source_module) do
    if Process.whereis(__MODULE__) do
      :ets.insert(@table_name, {{:file_depends_on, generated_file}, source_module})
    end

    :ok
  end

  @doc """
  Get all files that depend on a given module.

  Returns list of generated filenames that need regeneration.
  """
  def get_dependents(module) do
    try do
      :ets.match(@table_name, {{:file_depends_on, :"$1"}, module})
      |> Enum.map(&hd/1)
      |> Enum.uniq()
    rescue
      ArgumentError -> []
    end
  end

  @doc """
  Clear all dependencies for a generated file.

  Called before regenerating to allow fresh dependency tracking.
  """
  def clear_dependencies(generated_file) do
    if Process.whereis(__MODULE__) do
      :ets.match_delete(@table_name, {{:file_depends_on, generated_file}, :_})
    end

    :ok
  end

  @doc """
  Get the dependency graph as a map for debugging.
  """
  def dependency_graph do
    try do
      :ets.tab2list(@table_name)
      |> Enum.group_by(
        fn {{:file_depends_on, file}, _module} -> file end,
        fn {{:file_depends_on, _file}, module} -> module end
      )
    rescue
      ArgumentError -> %{}
    end
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:bag, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end
end
