defmodule NbTs.Registry do
  @moduledoc """
  Registry for NbSerializer serializers using ETS with O(1) lookups.

  This module provides a registry for tracking which serializer modules
  have been compiled and what TypeScript interface names they generate. It also
  detects namespace collisions where multiple serializers would generate the
  same TypeScript interface name.

  ## Architecture

  Uses TWO ETS tables for O(1) lookups in both directions:
  - `:nb_ts_serializers` - Maps module -> interface_name
  - `:nb_ts_serializer_names` - Maps interface_name -> module

  Both tables use:
  - `:set` - Each key can only appear once
  - `:public` - Can be accessed from any process
  - `:named_table` - Accessible via the table name atom
  - `read_concurrency: true` - Optimized for concurrent reads

  This allows O(1) collision detection even with hundreds of serializers.

  ## Example

      # Register a serializer
      NbTs.Registry.register(MyApp.UserSerializer)
      #=> {:ok, "User"}

      # Get all registered serializers
      NbTs.Registry.all_serializers()
      #=> [MyApp.UserSerializer, MyApp.PostSerializer]

      # Check for collision (O(1) lookup)
      NbTs.Registry.check_collision(MyApp.AnotherUserSerializer)
      #=> {:collision, MyApp.UserSerializer}
  """

  use GenServer

  @modules_table :nb_ts_serializers
  @names_table :nb_ts_serializer_names

  @type module_name :: module()
  @type interface_name :: String.t()
  @type collision :: {:collision, module_name()}

  # Client API

  @doc """
  Starts the registry GenServer.

  Called automatically by the application supervisor.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a serializer module.

  Extracts the TypeScript interface name from the module and stores the mapping.
  Checks for namespace collisions - if another module already generates the same
  interface name, returns an error tuple.

  ## Parameters

    - `module` - The serializer module to register

  ## Returns

    - `{:ok, interface_name}` - Successfully registered
    - `{:error, {:collision, interface_name, existing_module}}` - Collision detected

  ## Examples

      iex> NbTs.Registry.register(MyApp.UserSerializer)
      {:ok, "User"}

      iex> NbTs.Registry.register(MyApp.UserSerializer)
      {:ok, "User"}  # Idempotent - registering same module again is ok

      iex> NbTs.Registry.register(MyApp.AnotherUserSerializer)
      {:error, {:collision, "User", MyApp.UserSerializer}}
  """
  @spec register(module_name()) ::
          {:ok, interface_name()} | {:error, {:collision, interface_name(), module_name()}}
  def register(module) when is_atom(module) do
    interface_name = extract_interface_name(module)

    # O(1) collision check via ETS lookup
    case :ets.lookup(@names_table, interface_name) do
      [{^interface_name, ^module}] ->
        # Same module, same name - idempotent
        {:ok, interface_name}

      [{^interface_name, existing_module}] ->
        # Different module, same name - collision!
        {:error, {:collision, interface_name, existing_module}}

      [] ->
        # No collision, register it
        :ets.insert(@modules_table, {module, interface_name})
        :ets.insert(@names_table, {interface_name, module})
        {:ok, interface_name}
    end
  end

  @doc """
  Returns all registered serializer modules.

  ## Returns

  A list of module names that have been registered, sorted alphabetically.

  ## Examples

      iex> NbTs.Registry.all_serializers()
      [MyApp.PostSerializer, MyApp.UserSerializer]
  """
  @spec all_serializers() :: [module_name()]
  def all_serializers do
    :ets.tab2list(@modules_table)
    |> Enum.map(fn {module, _interface_name} -> module end)
    |> Enum.sort()
  rescue
    ArgumentError ->
      # Table doesn't exist yet
      []
  end

  @doc """
  Checks if registering a module would cause a namespace collision.

  Uses O(1) ETS lookup for fast collision detection.

  ## Parameters

    - `module` - The module to check

  ## Returns

    - `:ok` - No collision, safe to register
    - `{:collision, existing_module}` - Would collide with existing_module

  ## Examples

      iex> NbTs.Registry.check_collision(MyApp.ProductSerializer)
      :ok

      iex> NbTs.Registry.check_collision(MyApp.AnotherUserSerializer)
      {:collision, MyApp.UserSerializer}
  """
  @spec check_collision(module_name()) :: :ok | collision()
  def check_collision(module) when is_atom(module) do
    interface_name = extract_interface_name(module)

    # O(1) lookup
    case :ets.lookup(@names_table, interface_name) do
      [{^interface_name, ^module}] ->
        # Same module - no collision
        :ok

      [{^interface_name, existing_module}] ->
        # Different module - collision
        {:collision, existing_module}

      [] ->
        # Not registered - no collision
        :ok
    end
  rescue
    ArgumentError ->
      # Table doesn't exist yet
      :ok
  end

  @doc """
  Clears all registrations from the registry.

  Useful for testing. In production, registrations persist for the lifetime
  of the application.

  ## Examples

      iex> NbTs.Registry.clear()
      :ok
  """
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@modules_table)
    :ets.delete_all_objects(@names_table)
    :ok
  rescue
    ArgumentError ->
      :ok
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    # Create both ETS tables
    modules_table =
      :ets.new(@modules_table, [:set, :public, :named_table, read_concurrency: true])

    names_table =
      :ets.new(@names_table, [:set, :public, :named_table, read_concurrency: true])

    {:ok, %{modules_table: modules_table, names_table: names_table}}
  end

  # Private functions

  @spec extract_interface_name(module_name()) :: interface_name()
  defp extract_interface_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> String.replace(~r/Serializer$/, "")
  end
end
