defmodule NbTs.InertiaPropGenerationTest do
  use ExUnit.Case, async: false

  alias NbTs.Interface

  @moduledoc """
  Tests for TypeScript generation from Inertia props using the unified syntax.

  Unified syntax from nb_inertia:
  - prop :tags, list: :string
  - prop :users, list: UserSerializer
  - prop :status, enum: ["active", "inactive"]
  - prop :roles, list: [enum: ["admin", "user"]]
  """

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
end
