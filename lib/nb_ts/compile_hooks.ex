defmodule NbTs.CompileHooks do
  @moduledoc """
  Compile-time hooks for automatic TypeScript type regeneration.

  This module provides after-compile hooks that automatically regenerate
  TypeScript types when NbSerializer or NbInertia.Controller modules are
  recompiled during development.

  ## Usage

  In your serializer module:

      defmodule MyApp.UserSerializer do
        use NbSerializer.Serializer

        # TypeScript types will be automatically regenerated after compilation
        # if nb_ts is available (optional dependency)
      end

  In your controller module:

      defmodule MyAppWeb.UserController do
        use NbInertia.Controller

        inertia_page :index do
          prop :users, type: ~TS"Array<User>"
        end

        # TypeScript types will be automatically regenerated after compilation
        # if nb_ts is available (optional dependency)
      end

  ## Configuration

  Configure the output directory in your config:

      # config/dev.exs
      config :nb_ts,
        output_dir: "assets/js/types",
        auto_generate: true  # Enable auto-generation on compile (default: true in dev)

  ## How it works

  When a serializer or controller module is compiled:
  1. This hook is called via `@after_compile`
  2. It checks if auto-generation is enabled
  3. It incrementally regenerates only the types for the changed module
  4. Index file is updated to include the new/updated types

  This provides real-time TypeScript type updates during development without
  needing to manually run `mix nb_ts.gen`.
  """

  require Logger

  @doc """
  After-compile callback for NbSerializer and NbInertia.Controller modules.

  This is called automatically after a serializer or controller module is compiled.
  It triggers incremental TypeScript type generation for the compiled module.

  ## Parameters

    * `env` - Compilation environment containing module information
    * `_bytecode` - Compiled bytecode (unused)

  ## Returns

    * `:ok` - Always returns :ok to not interfere with compilation
  """
  def __after_compile__(env, _bytecode) do
    module = env.module

    # Skip if the TaskSupervisor isn't running yet (initial compilation before app start)
    unless supervisor_alive?() do
      :ok
    else
      cond do
        is_serializer_module?(module) ->
          if NbTs.Config.auto_generate?() do
            Task.Supervisor.start_child(NbTs.TaskSupervisor, fn ->
              regenerate_types_for_module(module, :serializer)
            end)
          end

        is_controller_module?(module) ->
          if NbTs.Config.auto_generate?() do
            Task.Supervisor.start_child(NbTs.TaskSupervisor, fn ->
              regenerate_types_for_module(module, :controller)
            end)
          end

        true ->
          :ok
      end
    end

    :ok
  end

  defp supervisor_alive? do
    pid = Process.whereis(NbTs.TaskSupervisor)
    is_pid(pid) and Process.alive?(pid)
  end

  # Check if the module is a serializer module
  defp is_serializer_module?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__nb_serializer_serialize__, 2) and
      function_exported?(module, :__nb_serializer_type_metadata__, 0)
  end

  # Check if the module is a controller module
  defp is_controller_module?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :inertia_page_config, 1)
  end

  # Regenerate types for a specific module
  defp regenerate_types_for_module(module, type) do
    output_dir = NbTs.Config.output_dir()

    # Use incremental generation for better performance
    opts =
      case type do
        :serializer -> [serializers: [module], output_dir: output_dir, validate: false]
        :controller -> [controllers: [module], output_dir: output_dir, validate: false]
      end

    {:ok, %{added: added, updated: updated}} = NbTs.Generator.generate_incremental(opts)

    if added > 0 or updated > 0 do
      module_name = inspect(module)
      Logger.debug("NbTs.CompileHooks: TypeScript types regenerated for #{module_name}")
    end

    :ok
  rescue
    error ->
      Logger.warning(
        "NbTs.CompileHooks: Error regenerating TypeScript types for #{inspect(module)}: #{inspect(error)}"
      )

      :error
  end
end
