defmodule NbTs.RpcDiscovery do
  @moduledoc """
  Discovers NbRpc procedure modules and routers for TypeScript generation.

  Finds modules that `use NbRpc.Procedure` by checking for the
  `__nb_rpc_procedures__/0` function, and modules that `use NbRpc.Router`
  by checking for `__nb_rpc_scopes__/0`.
  """

  @doc """
  Discovers all NbRpc.Procedure modules.

  Returns a list of modules that define RPC procedures (queries, mutations, subscriptions).
  """
  @spec discover_procedure_modules() :: [module()]
  def discover_procedure_modules do
    app = get_app_name()

    app_modules = get_app_modules(app)
    loaded_modules = :code.all_loaded() |> Enum.map(&elem(&1, 0))

    (app_modules ++ loaded_modules)
    |> Enum.uniq()
    |> Enum.filter(fn module ->
      Code.ensure_loaded?(module) and
        function_exported?(module, :__nb_rpc_procedures__, 0)
    end)
  end

  @doc """
  Discovers the NbRpc.Router module.

  Returns the router module if found, or nil.
  """
  @spec discover_router() :: module() | nil
  def discover_router do
    app = get_app_name()

    app_modules = get_app_modules(app)
    loaded_modules = :code.all_loaded() |> Enum.map(&elem(&1, 0))

    (app_modules ++ loaded_modules)
    |> Enum.uniq()
    |> Enum.find(fn module ->
      Code.ensure_loaded?(module) and
        function_exported?(module, :__nb_rpc_scopes__, 0)
    end)
  end

  @doc """
  Discovers router scopes and maps them to procedure modules.

  Returns a list of `{scope_prefix, procedure_module}` tuples.
  If no router is found, discovers procedure modules directly and
  infers scope names from module names.
  """
  @spec discover_scopes() :: [{String.t(), module()}]
  def discover_scopes do
    case discover_router() do
      nil ->
        # No router found, infer scopes from module names
        discover_procedure_modules()
        |> Enum.map(fn module ->
          scope = infer_scope_name(module)
          {scope, module}
        end)

      router ->
        router.__nb_rpc_scopes__()
        |> Enum.map(fn {prefix, module, _middleware} -> {prefix, module} end)
    end
  end

  @doc """
  Returns true if any NbRpc procedure modules are found.
  """
  @spec rpc_available?() :: boolean()
  def rpc_available? do
    discover_procedure_modules() != []
  end

  # -- Private --

  defp infer_scope_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  defp get_app_name do
    if Code.ensure_loaded?(Mix.Project) do
      Mix.Project.config()[:app]
    end
  end

  defp get_app_modules(app) do
    if app do
      case :application.get_key(app, :modules) do
        {:ok, modules} -> modules
        _ -> []
      end
    else
      []
    end
  end
end
