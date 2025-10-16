defmodule NbTs.CompileHooks do
  @moduledoc """
  Compile-time hooks for automatic TypeScript type regeneration.

  This module provides after-compile hooks that automatically regenerate
  TypeScript types when NbSerializer modules are recompiled during development.

  ## Usage

  In your serializer module:

      defmodule MyApp.UserSerializer do
        use NbSerializer.Serializer

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

  When a serializer module is compiled:
  1. This hook is called via `@after_compile`
  2. It checks if auto-generation is enabled
  3. It incrementally regenerates only the types for the changed module
  4. Index file is updated to include the new/updated types

  This provides real-time TypeScript type updates during development without
  needing to manually run `mix nb_ts.gen.types`.
  """

  require Logger

  @doc """
  After-compile callback for NbSerializer modules.

  This is called automatically after a serializer module is compiled.
  It triggers incremental TypeScript type generation for the compiled module.

  ## Parameters

    * `env` - Compilation environment containing module information
    * `_bytecode` - Compiled bytecode (unused)

  ## Returns

    * `:ok` - Always returns :ok to not interfere with compilation
  """
  def __after_compile__(env, _bytecode) do
    module = env.module

    # Only regenerate if this is a serializer module
    if is_serializer_module?(module) do
      # Check if auto-generation is enabled (default: true in dev, false in prod)
      if auto_generate_enabled?() do
        # Run regeneration asynchronously to not block compilation
        Task.start(fn ->
          regenerate_types_for_module(module)
        end)
      end
    end

    :ok
  end

  # Check if the module is a serializer module
  defp is_serializer_module?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__nb_serializer_serialize__, 2) and
      function_exported?(module, :__nb_serializer_type_metadata__, 0)
  end

  # Check if auto-generation is enabled
  defp auto_generate_enabled? do
    # Default to true in dev, false in prod
    default =
      case Mix.env() do
        :dev -> true
        :test -> false
        _ -> false
      end

    Application.get_env(:nb_ts, :auto_generate, default)
  end

  # Regenerate types for a specific module
  defp regenerate_types_for_module(module) do
    output_dir = Application.get_env(:nb_ts, :output_dir, "assets/js/types")

    try do
      # Use incremental generation for better performance
      case NbTs.Generator.generate_incremental(
             serializers: [module],
             output_dir: output_dir,
             validate: false
           ) do
        {:ok, %{added: added, updated: updated}} ->
          if added > 0 or updated > 0 do
            module_name = inspect(module)
            Logger.debug("TypeScript types regenerated for #{module_name}")
          end

        {:error, reason} ->
          Logger.warning(
            "Failed to regenerate TypeScript types for #{inspect(module)}: #{inspect(reason)}"
          )
      end
    rescue
      error ->
        Logger.warning(
          "Error regenerating TypeScript types for #{inspect(module)}: #{inspect(error)}"
        )
    end
  end
end
