defmodule Mix.Tasks.Compile.NbTs do
  @moduledoc """
  Custom Mix compiler for incremental TypeScript type generation.

  Integrates into Elixir's compilation pipeline to automatically generate
  TypeScript types when serializers or controllers change.

  ## Configuration

      config :nb_ts,
        output_dir: "assets/js/types",
        auto_generate: true

  Set `auto_generate: false` to disable automatic generation during compilation.
  """

  use Mix.Task.Compiler

  @manifest_file ".mix/compile.nb_ts"

  @doc """
  Runs the NbTs compiler.

  Returns:
  - `{:ok, []}` - Successfully generated types for changed modules
  - `{:noop, []}` - Skipped generation (disabled or no changes)
  - `{:error, []}` - Error during generation
  """
  def run(_args) do
    config = get_config()

    unless config[:auto_generate] do
      {:noop, []}
    else
      output_dir = config[:output_dir] || "assets/js/types"

      # Ensure output directory exists
      File.mkdir_p!(output_dir)

      # Get all current serializers and controllers
      current_modules = discover_all_modules()

      # Read previous manifest
      previous_manifest = read_manifest()

      # Detect changes
      {changed_serializers, changed_controllers, changed_rpc_procedures, new_manifest} =
        detect_changes(current_modules, previous_manifest)

      if changed_serializers == [] and changed_controllers == [] and changed_rpc_procedures == [] do
        # No changes detected
        {:noop, []}
      else
        # Generate types for changed modules
        result =
          NbTs.Generator.generate_incremental(
            serializers: changed_serializers,
            controllers: changed_controllers,
            rpc_procedures: changed_rpc_procedures,
            output_dir: output_dir
          )

        # Write updated manifest
        write_manifest(new_manifest)

        # Result will always be {:ok, stats} (validation is stubbed)
        {:ok, _stats} = result
        {:ok, []}
      end
    end
  rescue
    _ -> {:error, []}
  end

  @doc """
  Returns the list of manifest files used by this compiler.
  """
  def manifests do
    [@manifest_file]
  end

  @doc """
  Cleans the manifest file.
  """
  def clean do
    File.rm(@manifest_file)
    :ok
  end

  # Private functions

  defp get_config do
    # Support test mocking via :meck
    config = Mix.Project.config()
    Keyword.get(config, :nb_ts, [])
  end

  defp discover_all_modules do
    serializers = discover_serializers()
    controllers = discover_controllers()
    rpc_procedures = discover_rpc_procedures()

    %{
      serializers: serializers,
      controllers: controllers,
      rpc_procedures: rpc_procedures
    }
  end

  defp discover_serializers do
    # Get from registry first
    registered =
      if Process.whereis(NbTs.Registry) do
        NbTs.Registry.all_serializers()
      else
        []
      end

    # If registry is empty, scan loaded modules
    if registered == [] do
      loaded_modules = :code.all_loaded() |> Enum.map(&elem(&1, 0))

      loaded_modules
      |> Enum.filter(fn module ->
        Code.ensure_loaded?(module) &&
          function_exported?(module, :__nb_serializer_serialize__, 2) &&
          function_exported?(module, :__nb_serializer_type_metadata__, 0)
      end)
    else
      registered
    end
  end

  defp discover_controllers do
    loaded_modules = :code.all_loaded() |> Enum.map(&elem(&1, 0))

    loaded_modules
    |> Enum.filter(fn module ->
      Code.ensure_loaded?(module) &&
        function_exported?(module, :inertia_page_config, 1)
    end)
  end

  defp discover_rpc_procedures do
    if Code.ensure_loaded?(NbTs.RpcDiscovery) do
      NbTs.RpcDiscovery.discover_procedure_modules()
    else
      []
    end
  end

  defp detect_changes(current_modules, previous_manifest) do
    current_serializers = current_modules.serializers
    current_controllers = current_modules.controllers
    current_rpc_procedures = Map.get(current_modules, :rpc_procedures, [])

    # Build new manifest with current hashes
    new_manifest =
      Map.new(current_serializers ++ current_controllers ++ current_rpc_procedures, fn module ->
        {module, get_module_hash(module)}
      end)

    # Detect which modules changed
    changed_serializers =
      Enum.filter(current_serializers, fn module ->
        changed?(module, previous_manifest, new_manifest)
      end)

    changed_controllers =
      Enum.filter(current_controllers, fn module ->
        changed?(module, previous_manifest, new_manifest)
      end)

    changed_rpc_procedures =
      Enum.filter(current_rpc_procedures, fn module ->
        changed?(module, previous_manifest, new_manifest)
      end)

    {changed_serializers, changed_controllers, changed_rpc_procedures, new_manifest}
  end

  defp changed?(module, previous_manifest, new_manifest) do
    previous_hash = Map.get(previous_manifest, module)
    current_hash = Map.get(new_manifest, module)

    # Module is considered changed if:
    # 1. It's new (not in previous manifest)
    # 2. Its hash changed
    previous_hash == nil || previous_hash != current_hash
  end

  defp get_module_hash(module) do
    # Get module's bytecode and hash it
    case :code.get_object_code(module) do
      {^module, bytecode, _filename} ->
        :erlang.md5(bytecode)

      :error ->
        # Module not loaded, use empty hash
        :erlang.md5("")
    end
  end

  defp read_manifest do
    case File.read(@manifest_file) do
      {:ok, content} ->
        :erlang.binary_to_term(content)

      {:error, _} ->
        %{}
    end
  end

  defp write_manifest(data) do
    manifest_dir = Path.dirname(@manifest_file)
    File.mkdir_p!(manifest_dir)
    content = :erlang.term_to_binary(data)
    File.write!(@manifest_file, content)
  end
end
