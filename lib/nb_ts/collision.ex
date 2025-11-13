defmodule NbTs.Collision do
  @moduledoc """
  TypeScript type name collision detection and reporting.

  Detects when multiple Inertia pages would generate the same TypeScript
  interface name, which would cause duplicate exports and compilation errors.

  ## Examples

      pages = [
        {MyAppWeb.UserController, [index: %{component: "Users/Index"}, show: %{component: "Users/Show"}]},
        {MyAppWeb.AdminController, [users: %{component: "Users/Index"}]}
      ]

      NbTs.Collision.check_type_name_collisions(pages)
      # Warns: TypeScript type name collision detected: UsersIndexProps
  """

  @type controller :: module()
  @type page_name :: atom()
  @type page_config :: map()
  @type component_name :: String.t()
  @type type_name :: String.t()
  @type source :: {controller(), page_name(), component_name()}
  @type controller_pages :: {controller(), [{page_name(), page_config()}]}

  @doc """
  Checks for TypeScript type name collisions across Inertia pages.

  Scans all Inertia pages and identifies cases where multiple pages would
  generate the same TypeScript interface name. Emits compile warnings for
  each collision detected.

  ## Parameters

    - `inertia_pages` - List of {controller, pages} tuples from Discovery

  ## Returns

    - `:ok` - Always returns :ok (warnings are emitted as side effects)

  ## Examples

      iex> pages = [{MyAppWeb.UserController, [index: %{component: "Users/Index"}]}]
      iex> NbTs.Collision.check_type_name_collisions(pages)
      :ok
  """
  @spec check_type_name_collisions([controller_pages()]) :: :ok
  def check_type_name_collisions(inertia_pages) do
    # Build a map of generated type names to their sources
    type_name_to_sources =
      Enum.reduce(inertia_pages, %{}, fn {controller, pages}, acc ->
        Enum.reduce(pages, acc, fn {page_name, page_config}, inner_acc ->
          # Get the component name
          component_name = page_config.component

          # Determine the type name that will be generated
          type_name =
            case Map.get(page_config, :type_name) do
              nil -> component_name_to_page_interface(component_name)
              custom_name -> custom_name
            end

          # Track the source (controller + page_name)
          source = {controller, page_name, component_name}

          # Add to the map
          Map.update(inner_acc, type_name, [source], fn existing_sources ->
            [source | existing_sources]
          end)
        end)
      end)

    # Find collisions (type names with multiple sources)
    collisions =
      type_name_to_sources
      |> Enum.filter(fn {_type_name, sources} -> length(sources) > 1 end)
      |> Map.new()

    # Emit warnings for each collision
    Enum.each(collisions, fn {type_name, sources} ->
      emit_collision_warning(type_name, sources)
    end)

    :ok
  end

  # Private functions

  @spec component_name_to_page_interface(component_name()) :: type_name()
  defp component_name_to_page_interface(component_name) do
    component_name
    |> String.replace("/", "")
    |> String.replace(" ", "")
    |> Kernel.<>("Props")
  end

  @spec emit_collision_warning(type_name(), [source()]) :: :ok
  defp emit_collision_warning(type_name, sources) do
    # Format the list of conflicting pages
    source_list =
      sources
      # Reverse to show in order they were discovered
      |> Enum.reverse()
      |> Enum.map_join("\n  - ", fn {controller, page_name, component_name} ->
        "#{inspect(controller)}.#{page_name} (component: \"#{component_name}\")"
      end)

    # Get the first source's component name for the suggestion
    {_first_controller, first_page_name, first_component_name} = List.first(sources)

    IO.warn("""
    TypeScript type name collision detected: #{type_name}

    Multiple Inertia pages are generating the same TypeScript interface name:
      - #{source_list}

    This will cause duplicate exports in your generated TypeScript types file, leading to compilation errors.

    Solutions:
      1. Use the type_name option to provide unique names for each page:

         inertia_page #{inspect(first_page_name)},
           component: "#{first_component_name}",
           type_name: "UniquePageNameProps" do
           # ...
         end

      2. Use different component paths for each controller (recommended)

    See: https://hexdocs.pm/nb_inertia/NbInertia.Controller.html#inertia_page/3
    """)
  end
end
