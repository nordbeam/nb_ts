defmodule NbTs.IndexExportTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    output_dir = Path.join(tmp_dir, "types")
    File.mkdir_p!(output_dir)

    # Start dependencies if not already started
    unless Process.whereis(NbTs.Registry) do
      start_supervised!({NbTs.Registry, []})
    end

    unless Process.whereis(NbTs.DependencyTracker) do
      start_supervised!({NbTs.DependencyTracker, []})
    end

    {:ok, output_dir: output_dir}
  end

  describe "index.ts export generation" do
    test "exports both Props and FormInputs interfaces when page has forms", %{
      output_dir: output_dir
    } do
      defmodule TestControllerWithForms do
        def __inertia_pages__ do
          %{
            spaces_new: %{
              component: "Spaces/New",
              props: [],
              forms: %{
                space: [
                  {:name, :string, []},
                  {:description, :string, [optional: true]}
                ]
              }
            }
          }
        end

        def __inertia_forms__ do
          %{
            space: [
              {:name, :string, []},
              {:description, :string, [optional: true]}
            ]
          }
        end

        def inertia_shared_props, do: []
        def __inertia_shared_modules__, do: []
      end

      # Generate types
      {:ok, _results} =
        NbTs.Generator.generate_incremental(
          serializers: [],
          controllers: [TestControllerWithForms],
          shared_props: [],
          output_dir: output_dir
        )

      # Check that both interface files exist
      props_file = Path.join(output_dir, "SpacesNewProps.ts")
      assert File.exists?(props_file)

      # Check content of Props file - should have both interfaces
      content = File.read!(props_file)
      assert content =~ "export interface SpacesNewProps"
      assert content =~ "export interface SpacesNewFormInputs"

      # Check index.ts
      index_file = Path.join(output_dir, "index.ts")
      assert File.exists?(index_file)

      index_content = File.read!(index_file)

      # Should export BOTH interfaces from the same file
      assert index_content =~ ~r/export type \{.*SpacesNewFormInputs.*,.*SpacesNewProps.*\}/,
             "index.ts should export both FormInputs and Props interfaces"

      # Verify exact format: should be on one line
      assert index_content =~
               ~r/export type \{ SpacesNewFormInputs, SpacesNewProps \} from "\.\/SpacesNewProps";/
    end

    test "exports only Props interface when page has no forms", %{output_dir: output_dir} do
      defmodule TestControllerWithoutForms do
        def __inertia_pages__ do
          %{
            users_index: %{
              component: "Users/Index",
              props: [%{name: :users, type: :list, opts: []}]
            }
          }
        end

        def __inertia_forms__, do: %{}

        def inertia_shared_props, do: []
        def __inertia_shared_modules__, do: []
      end

      # Generate types
      {:ok, _results} =
        NbTs.Generator.generate_incremental(
          serializers: [],
          controllers: [TestControllerWithoutForms],
          shared_props: [],
          output_dir: output_dir
        )

      # Check index.ts
      index_file = Path.join(output_dir, "index.ts")
      assert File.exists?(index_file)

      index_content = File.read!(index_file)

      # Should only export Props interface
      assert index_content =~ ~r/export type \{ UsersIndexProps \}/
      # Should NOT mention FormInputs
      refute index_content =~ "FormInputs"
    end

    test "handles multiple pages with mixed forms", %{output_dir: output_dir} do
      defmodule TestControllerMixed do
        def __inertia_pages__ do
          %{
            users_new: %{
              component: "Users/New",
              props: [],
              forms: %{
                user: [
                  {:name, :string, []}
                ]
              }
            },
            users_index: %{
              component: "Users/Index",
              props: []
              # No forms for this page
            }
          }
        end

        def __inertia_forms__ do
          %{
            # Only users_new has a form
            user: [
              {:name, :string, []}
            ]
          }
        end

        def inertia_shared_props, do: []
        def __inertia_shared_modules__, do: []
      end

      # Generate types
      {:ok, _results} =
        NbTs.Generator.generate_incremental(
          serializers: [],
          controllers: [TestControllerMixed],
          shared_props: [],
          output_dir: output_dir
        )

      # Check index.ts
      index_file = Path.join(output_dir, "index.ts")
      index_content = File.read!(index_file)

      # UsersNew should have both Props and FormInputs
      assert index_content =~ ~r/UsersNewFormInputs/
      assert index_content =~ ~r/UsersNewProps/

      # UsersIndex should only have Props
      assert index_content =~ ~r/UsersIndexProps/
      refute index_content =~ "UsersIndexFormInputs"
    end

    test "alphabetically sorts interface names within same file", %{output_dir: output_dir} do
      defmodule TestAlphabeticOrder do
        def __inertia_pages__ do
          %{
            test: %{
              component: "Test",
              props: [],
              forms: %{
                data: [{:field, :string, []}]
              }
            }
          }
        end

        def __inertia_forms__ do
          %{
            data: [{:field, :string, []}]
          }
        end

        def inertia_shared_props, do: []
        def __inertia_shared_modules__, do: []
      end

      {:ok, _results} =
        NbTs.Generator.generate_incremental(
          serializers: [],
          controllers: [TestAlphabeticOrder],
          shared_props: [],
          output_dir: output_dir
        )

      index_file = Path.join(output_dir, "index.ts")
      index_content = File.read!(index_file)

      # FormInputs should come before Props alphabetically
      assert index_content =~
               ~r/export type \{ TestFormInputs, TestProps \} from "\.\/TestProps";/
    end
  end
end
