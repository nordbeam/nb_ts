defmodule NbTs.SerializerGenerationTest do
  use ExUnit.Case, async: false

  alias NbTs.Interface
  alias NbTs.TypeMapper

  @moduledoc """
  Tests for TypeScript generation from NbSerializer fields using the new unified syntax.

  New field format from NbSerializer:
  - {:tags, [list: :string]}                      → tags: string[]
  - {:status, [enum: ["active", "inactive"]]}     → status: "active" | "inactive"
  - {:statuses, [list: [enum: [...]]]}            → statuses: ("a" | "b")[]
  - {:config, [serializer: ConfigSerializer]}     → config: Config
  - {:name, [type: :string]}                      → name: string
  """

  describe "TypeMapper.to_typescript/1 with new unified syntax" do
    test "handles simple typed fields" do
      assert TypeMapper.to_typescript(%{type: :string}) == "string"
      assert TypeMapper.to_typescript(%{type: :number}) == "number"
      assert TypeMapper.to_typescript(%{type: :integer}) == "number"
      assert TypeMapper.to_typescript(%{type: :boolean}) == "boolean"
    end

    test "handles enum fields" do
      type_info = %{enum: ["active", "inactive", "pending"]}
      assert TypeMapper.to_typescript(type_info) == ~s("active" | "inactive" | "pending")
    end

    test "handles list of primitives" do
      type_info = %{type: :string, list: true}
      result = TypeMapper.to_typescript(type_info)
      # Should return just the base type, modifiers applied separately
      assert result == "string"
    end

    test "handles list of enums" do
      # New format: list: [enum: [...]]
      type_info = %{list: [enum: ["active", "inactive"]]}
      result = TypeMapper.to_typescript(type_info)
      # Should handle nested list with enum
      assert result == "(\"active\" | \"inactive\")[]"
    end

    test "handles nullable fields" do
      type_info = %{type: :string, nullable: true}
      # TypeMapper returns base type, modifiers applied by apply_modifiers
      assert TypeMapper.to_typescript(type_info) == "string"
    end

    test "handles custom TypeScript types" do
      type_info = %{type: "Record<string, any>", custom: true}
      assert TypeMapper.to_typescript(type_info) == "Record<string, any>"
    end
  end

  describe "TypeMapper.apply_modifiers/2" do
    test "applies list modifier" do
      base_type = "string"
      type_info = %{list: true}
      assert TypeMapper.apply_modifiers(base_type, type_info) == "Array<string>"
    end

    test "applies nullable modifier" do
      base_type = "string"
      type_info = %{nullable: true}
      assert TypeMapper.apply_modifiers(base_type, type_info) == "string | null"
    end

    test "applies both list and nullable modifiers" do
      base_type = "string"
      type_info = %{list: true, nullable: true}
      assert TypeMapper.apply_modifiers(base_type, type_info) == "Array<string> | null"
    end
  end

  describe "Interface.build/1 with new field format" do
    test "generates TypeScript for serializer with typed list field" do
      defmodule TestTagsSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            id: %{type: :integer, optional: false, nullable: false},
            tags: %{type: :string, list: true, optional: false, nullable: false}
          }
        end
      end

      TestTagsSerializer.__nb_serializer_ensure_registered__()
      interface = Interface.build(TestTagsSerializer)
      typescript = Interface.to_typescript(interface)

      assert typescript =~ "export interface TestTags"
      assert typescript =~ "tags: Array<string>;"
    end

    test "generates TypeScript for serializer with enum field" do
      defmodule TestStatusSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            id: %{type: :integer, optional: false, nullable: false},
            status: %{enum: ["active", "inactive", "pending"], optional: false, nullable: false}
          }
        end
      end

      TestStatusSerializer.__nb_serializer_ensure_registered__()
      interface = Interface.build(TestStatusSerializer)
      typescript = Interface.to_typescript(interface)

      assert typescript =~ "export interface TestStatus"
      assert typescript =~ ~s(status: "active" | "inactive" | "pending";)
    end

    test "generates TypeScript for serializer with list of enums" do
      defmodule TestStatusesSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            id: %{type: :integer, optional: false, nullable: false},
            statuses: %{
              list: [enum: ["active", "inactive"]],
              optional: false,
              nullable: false
            }
          }
        end
      end

      TestStatusesSerializer.__nb_serializer_ensure_registered__()
      interface = Interface.build(TestStatusesSerializer)
      typescript = Interface.to_typescript(interface)

      assert typescript =~ "export interface TestStatuses"
      # Should generate: statuses: ("active" | "inactive")[]
      assert typescript =~ "statuses: (\"active\" | \"inactive\")[];"
    end

    test "generates TypeScript for serializer with nested serializer reference" do
      defmodule TestConfigSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            enabled: %{type: :boolean, optional: false, nullable: false}
          }
        end
      end

      defmodule TestWidgetSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            id: %{type: :integer, optional: false, nullable: false},
            config: %{
              serializer: TestConfigSerializer,
              optional: false,
              nullable: false
            }
          }
        end
      end

      TestConfigSerializer.__nb_serializer_ensure_registered__()
      TestWidgetSerializer.__nb_serializer_ensure_registered__()

      interface = Interface.build(TestWidgetSerializer)
      typescript = Interface.to_typescript(interface)

      assert typescript =~ "export interface TestWidget"
      assert typescript =~ "config: TestConfig;"
      assert typescript =~ ~s(import type { TestConfig } from "./TestConfigSerializer";)
    end

    test "generates TypeScript for serializer with nullable enum" do
      defmodule TestNullableEnumSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            status: %{
              enum: ["active", "inactive"],
              optional: false,
              nullable: true
            }
          }
        end
      end

      TestNullableEnumSerializer.__nb_serializer_ensure_registered__()
      interface = Interface.build(TestNullableEnumSerializer)
      typescript = Interface.to_typescript(interface)

      assert typescript =~ "export interface TestNullableEnum"
      assert typescript =~ ~s(status: "active" | "inactive" | null;)
    end

    test "generates TypeScript for serializer with optional list" do
      defmodule TestOptionalListSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            tags: %{
              type: :string,
              list: true,
              optional: true,
              nullable: false
            }
          }
        end
      end

      TestOptionalListSerializer.__nb_serializer_ensure_registered__()
      interface = Interface.build(TestOptionalListSerializer)
      typescript = Interface.to_typescript(interface)

      assert typescript =~ "export interface TestOptionalList"
      assert typescript =~ "tags?: Array<string>;"
    end

    test "generates TypeScript for complex serializer with multiple field types" do
      defmodule TestComplexSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            id: %{type: :integer, optional: false, nullable: false},
            name: %{type: :string, optional: false, nullable: false},
            tags: %{type: :string, list: true, optional: false, nullable: false},
            status: %{enum: ["active", "inactive"], optional: false, nullable: false},
            roles: %{
              list: [enum: ["admin", "user", "guest"]],
              optional: true,
              nullable: false
            },
            metadata: %{type: :any, optional: true, nullable: true}
          }
        end
      end

      TestComplexSerializer.__nb_serializer_ensure_registered__()
      interface = Interface.build(TestComplexSerializer)
      typescript = Interface.to_typescript(interface)

      assert typescript =~ "export interface TestComplex"
      assert typescript =~ "id: number;"
      assert typescript =~ "name: string;"
      assert typescript =~ "tags: Array<string>;"
      assert typescript =~ "status: \"active\" | \"inactive\";"
      assert typescript =~ "roles?: (\"admin\" | \"user\" | \"guest\")[];"
      assert typescript =~ "metadata?: any | null;"
    end
  end

  describe "backwards compatibility" do
    test "still handles old format with fields as list" do
      defmodule TestLegacySerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            fields: [
              %{name: :id, type: :integer, opts: []},
              %{name: :name, type: :string, opts: []}
            ]
          }
        end
      end

      TestLegacySerializer.__nb_serializer_ensure_registered__()
      interface = Interface.build(TestLegacySerializer)
      typescript = Interface.to_typescript(interface)

      assert typescript =~ "export interface TestLegacy"
      assert typescript =~ "id: number;"
      assert typescript =~ "name: string;"
    end
  end
end
