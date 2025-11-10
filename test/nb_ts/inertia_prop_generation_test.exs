defmodule NbTs.InertiaPropGenerationTest do
  @moduledoc """
  Tests for TypeScript generation from Inertia props using the unified syntax.

  Unified syntax from nb_inertia:
  - prop :tags, list: :string
  - prop :users, list: UserSerializer
  - prop :status, enum: ["active", "inactive"]
  - prop :roles, list: [enum: ["admin", "user"]]
  """

  use ExUnit.Case, async: false

  alias NbTs.Interface

  describe "TypeScript generation for unified prop syntax" do
    test "generates correct TypeScript for prop with list: :string" do
      prop_config = %{
        name: :tags,
        opts: [list: :string]
      }

      page_config = %{
        component: "TestPage",
        props: [prop_config]
      }

      typescript = Interface.generate_page_interface(:test_page, page_config, [], [])

      assert typescript =~ "tags: string[]"
    end

    test "generates correct TypeScript for prop with list: SerializerModule" do
      defmodule TestPropUserSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            id: %{type: :integer, optional: false, nullable: false},
            name: %{type: :string, optional: false, nullable: false}
          }
        end
      end

      TestPropUserSerializer.__nb_serializer_ensure_registered__()

      prop_config = %{
        name: :users,
        opts: [list: TestPropUserSerializer]
      }

      page_config = %{
        component: "TestPage",
        props: [prop_config]
      }

      typescript = Interface.generate_page_interface(:test_page, page_config, [], [])

      assert typescript =~ "users: TestPropUser[]"
      assert typescript =~ ~s(import type { TestPropUser } from)
    end

    test "generates correct TypeScript for prop with enum" do
      prop_config = %{
        name: :status,
        opts: [enum: ["active", "inactive", "pending"]]
      }

      page_config = %{
        component: "TestPage",
        props: [prop_config]
      }

      typescript = Interface.generate_page_interface(:test_page, page_config, [], [])

      assert typescript =~ ~s(status: "active" | "inactive" | "pending")
    end

    test "generates correct TypeScript for prop with list: [enum: [...]]" do
      prop_config = %{
        name: :roles,
        opts: [list: [enum: ["admin", "user", "guest"]]]
      }

      page_config = %{
        component: "TestPage",
        props: [prop_config]
      }

      typescript = Interface.generate_page_interface(:test_page, page_config, [], [])

      assert typescript =~ ~r/roles: \("admin" \| "user" \| "guest"\)\[\]/
    end

    test "generates correct TypeScript for optional prop with list: :string" do
      prop_config = %{
        name: :tags,
        opts: [list: :string, optional: true]
      }

      page_config = %{
        component: "TestPage",
        props: [prop_config]
      }

      typescript = Interface.generate_page_interface(:test_page, page_config, [], [])

      assert typescript =~ "tags?: string[]"
    end

    test "generates correct TypeScript for nullable enum" do
      prop_config = %{
        name: :priority,
        opts: [enum: ["low", "high"], nullable: true]
      }

      page_config = %{
        component: "TestPage",
        props: [prop_config]
      }

      typescript = Interface.generate_page_interface(:test_page, page_config, [], [])

      assert typescript =~ ~s(priority: "low" | "high" | null)
    end

    test "generates correct TypeScript for optional list of serializers" do
      defmodule TestPropProductSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            id: %{type: :integer, optional: false, nullable: false}
          }
        end
      end

      TestPropProductSerializer.__nb_serializer_ensure_registered__()

      prop_config = %{
        name: :products,
        opts: [list: TestPropProductSerializer, optional: true]
      }

      page_config = %{
        component: "TestPage",
        props: [prop_config]
      }

      typescript = Interface.generate_page_interface(:test_page, page_config, [], [])

      assert typescript =~ "products?: TestPropProduct[]"
      assert typescript =~ ~s(import type { TestPropProduct } from)
    end

    test "complex page with multiple unified prop types" do
      defmodule TestPropItemSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            id: %{type: :integer, optional: false, nullable: false},
            title: %{type: :string, optional: false, nullable: false}
          }
        end
      end

      TestPropItemSerializer.__nb_serializer_ensure_registered__()

      page_config = %{
        component: "ComplexPage",
        props: [
          %{name: :id, type: :integer, opts: []},
          %{name: :name, type: :string, opts: []},
          %{name: :tags, opts: [list: :string]},
          %{name: :items, opts: [list: TestPropItemSerializer]},
          %{name: :status, opts: [enum: ["draft", "published"]]},
          %{name: :permissions, opts: [list: [enum: ["read", "write"]]]},
          %{name: :priority, opts: [enum: ["low", "high"], optional: true]}
        ]
      }

      typescript = Interface.generate_page_interface(:complex_page, page_config, [], [])

      # Check all fields are generated correctly
      assert typescript =~ "id: number"
      assert typescript =~ "name: string"
      assert typescript =~ "tags: string[]"
      assert typescript =~ "items: TestPropItem[]"
      assert typescript =~ ~s(status: "draft" | "published")
      assert typescript =~ ~r/permissions: \("read" \| "write"\)\[\]/
      assert typescript =~ ~s(priority?: "low" | "high")
      assert typescript =~ ~s(import type { TestPropItem } from)
    end
  end

  describe "custom type_name option" do
    test "uses custom type_name instead of generating from component" do
      page_config = %{
        component: "Public/WidgetShow",
        type_name: "WidgetPreviewProps",
        props: [
          %{name: :widget, type: :map, opts: []},
          %{name: :settings, type: :map, opts: []}
        ]
      }

      typescript = Interface.generate_page_interface(:preview, page_config, [], [])

      # Should use custom type_name
      assert typescript =~ "export interface WidgetPreviewProps"
      # Should NOT use the component-derived name
      refute typescript =~ "PublicWidgetShowProps"
    end

    test "generates FormInputs interface with matching custom type_name" do
      page_config = %{
        component: "Public/WidgetShow",
        type_name: "WidgetPreviewProps",
        props: [
          %{name: :widget, type: :map, opts: []}
        ],
        forms: %{
          widget: [
            {:name, :string, []},
            {:enabled, :boolean, []}
          ]
        }
      }

      typescript = Interface.generate_page_interface(:preview, page_config, [], [])

      # Props interface should use custom name
      assert typescript =~ "export interface WidgetPreviewProps"
      # FormInputs interface should derive from custom name
      assert typescript =~ "export interface WidgetPreviewFormInputs"
      # Should NOT use the component-derived names
      refute typescript =~ "PublicWidgetShowProps"
      refute typescript =~ "PublicWidgetShowFormInputs"
    end

    test "falls back to component-based name when type_name not provided" do
      page_config = %{
        component: "Users/Index",
        props: [
          %{name: :users, type: :list, opts: []}
        ]
      }

      typescript = Interface.generate_page_interface(:index, page_config, [], [])

      # Should use component-derived name
      assert typescript =~ "export interface UsersIndexProps"
    end

    test "custom type_name works with shared props" do
      defmodule TestCustomTypeNameSharedProps do
        def __inertia_shared_props__ do
          [
            %{name: :current_user, type: :map, opts: []}
          ]
        end

        def build_props(_conn, _opts) do
          %{current_user: %{id: 1}}
        end
      end

      page_config = %{
        component: "Public/WidgetShow",
        type_name: "CustomWidgetProps",
        props: [
          %{name: :widget, type: :map, opts: []}
        ]
      }

      typescript =
        Interface.generate_page_interface(:show, page_config, [TestCustomTypeNameSharedProps], [])

      # Should use custom type_name
      assert typescript =~ "export interface CustomWidgetProps"
      # Should extend shared props
      assert typescript =~ "extends TestCustomTypeNameSharedPropsProps"
    end
  end
end
