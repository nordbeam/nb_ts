defmodule NbTs.Discovery do
  @moduledoc """
  Module discovery for TypeScript generation.

  Discovers serializers, Inertia controllers/pages, and SharedProps modules
  across the application. Uses the application's loaded modules and registered
  modules to find all relevant code.

  ## Discovery Strategy

  1. Check the application's compiled modules (:application.get_key/2)
  2. Check all loaded modules (:code.all_loaded/0)
  3. Filter by module signatures (exported functions)
  4. Ensure modules are loaded and registered

  This approach works in both development and production environments.
  """

  @type module_name :: module()
  @type page_config :: map()
  @type controller_pages :: {module_name(), [{atom(), page_config()}]}

  @doc """
  Discovers all NbSerializer serializer modules.

  ## Returns

  A list of serializer modules that have been registered or found in the application.

  ## Examples

      iex> NbTs.Discovery.discover_serializers()
      [MyApp.UserSerializer, MyApp.PostSerializer]
  """
  @spec discover_serializers() :: [module_name()]
  def discover_serializers do
    registered =
      if Process.whereis(NbTs.Registry) do
        NbTs.Registry.all_serializers()
      else
        []
      end

    if registered == [] do
      serializers = find_all_serializers()

      # Ensure all serializers are registered
      Enum.each(serializers, fn module ->
        if function_exported?(module, :__nb_serializer_ensure_registered__, 0) do
          module.__nb_serializer_ensure_registered__()
        end
      end)

      serializers
    else
      registered
    end
  end

  @doc """
  Discovers all SharedProps modules.

  SharedProps modules are used to define props that are shared across all Inertia pages.

  ## Returns

  A list of SharedProps modules found in the application.

  ## Examples

      iex> NbTs.Discovery.discover_shared_props_modules()
      [MyAppWeb.SharedProps.Auth, MyAppWeb.SharedProps.Locale]
  """
  @spec discover_shared_props_modules() :: [module_name()]
  def discover_shared_props_modules do
    app = get_app_name()

    app_modules = get_app_modules(app)
    loaded_modules = :code.all_loaded() |> Enum.map(&elem(&1, 0))

    (app_modules ++ loaded_modules)
    |> Enum.uniq()
    |> Enum.filter(fn module ->
      Code.ensure_loaded?(module) &&
        function_exported?(module, :__inertia_shared_props__, 0) &&
        function_exported?(module, :build_props, 2)
    end)
  end

  @doc """
  Discovers all Inertia controller modules and their pages.

  ## Returns

  A list of tuples containing the controller module and its page configurations.

  ## Examples

      iex> NbTs.Discovery.discover_inertia_pages()
      [
        {MyAppWeb.UserController, [users_index: %{component: "Users/Index", ...}]},
        {MyAppWeb.PostController, [posts_show: %{component: "Posts/Show", ...}]}
      ]
  """
  @spec discover_inertia_pages() :: [controller_pages()]
  def discover_inertia_pages do
    app = get_app_name()

    app_modules = get_app_modules(app)
    loaded_modules = :code.all_loaded() |> Enum.map(&elem(&1, 0))

    controllers =
      (app_modules ++ loaded_modules)
      |> Enum.uniq()
      |> Enum.filter(fn module ->
        Code.ensure_loaded?(module) &&
          function_exported?(module, :inertia_page_config, 1)
      end)

    controllers
    |> Enum.map(fn controller ->
      pages = get_controller_pages(controller)
      {controller, pages}
    end)
    |> Enum.reject(fn {_controller, pages} -> pages == [] end)
  end

  # Private functions

  @spec find_all_serializers() :: [module_name()]
  defp find_all_serializers do
    app = get_app_name()

    app_modules = get_app_modules(app)
    loaded_modules = :code.all_loaded() |> Enum.map(&elem(&1, 0))

    (app_modules ++ loaded_modules)
    |> Enum.uniq()
    |> Enum.filter(fn module ->
      Code.ensure_loaded?(module) &&
        function_exported?(module, :__nb_serializer_serialize__, 2) &&
        function_exported?(module, :__nb_serializer_type_metadata__, 0)
    end)
  end

  @spec get_controller_pages(module_name()) :: [{atom(), page_config()}]
  defp get_controller_pages(controller) do
    functions = controller.__info__(:functions)

    page_functions =
      Enum.filter(functions, fn {name, arity} ->
        name == :page && arity == 1
      end)

    if page_functions == [] do
      []
    else
      try do
        discover_page_names_from_module(controller)
      rescue
        _ -> []
      end
    end
  end

  @spec discover_page_names_from_module(module_name()) :: [{atom(), page_config()}]
  defp discover_page_names_from_module(controller) do
    if function_exported?(controller, :__inertia_pages__, 0) do
      controller.__inertia_pages__()
      |> Enum.map(fn {page_name, _config} ->
        config = controller.inertia_page_config(page_name)
        {page_name, config}
      end)
    else
      []
    end
  end

  @spec get_app_name() :: atom() | nil
  defp get_app_name do
    if Code.ensure_loaded?(Mix.Project) do
      Mix.Project.config()[:app]
    end
  end

  @spec get_app_modules(atom() | nil) :: [module_name()]
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
