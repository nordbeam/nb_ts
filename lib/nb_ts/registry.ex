defmodule NbTs.Registry do
  @moduledoc """
  Registry for NbSerializer serializers using GenServer with ETS backing.
  """
  use GenServer

  @table_name :nb_ts_serializers

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{table: table, namespaces: %{}}}
  end

  @doc """
  Register a serializer module.
  """
  def register(module) when is_atom(module) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:register, module})
    else
      :ok
    end
  end

  @doc """
  Get all registered serializers.
  """
  def all_serializers do
    try do
      :ets.tab2list(@table_name)
      |> Enum.map(fn {module, _} -> module end)
    rescue
      # Table doesn't exist
      ArgumentError -> []
    end
  end

  @doc """
  Check for namespace collisions.
  """
  def check_collision(module) do
    GenServer.call(__MODULE__, {:check_collision, module})
  end

  @impl true
  def handle_call({:register, module}, _from, state) do
    interface_name = extract_interface_name(module)

    # Check for namespace collision
    existing = Map.get(state.namespaces, interface_name)

    result =
      if existing && existing != module do
        {:error, {:collision, interface_name, existing}}
      else
        :ets.insert(@table_name, {module, interface_name})
        {:ok, interface_name}
      end

    new_state =
      if is_tuple(result) && elem(result, 0) == :ok do
        %{state | namespaces: Map.put(state.namespaces, interface_name, module)}
      else
        state
      end

    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:check_collision, module}, _from, state) do
    interface_name = extract_interface_name(module)
    existing = Map.get(state.namespaces, interface_name)

    result =
      if existing && existing != module do
        {:collision, existing}
      else
        :ok
      end

    {:reply, result, state}
  end

  defp extract_interface_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> String.replace(~r/Serializer$/, "")
  end
end
