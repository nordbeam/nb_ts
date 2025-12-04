defmodule NbTs.IntegrationTest do
  use ExUnit.Case, async: false

  alias NbTs.Generator

  @moduledoc """
  Integration tests that simulate real-world usage with NbSerializer metadata format.

  These tests verify that TypeScript generation works correctly with the metadata
  format that NbSerializer actually produces.
  """

  @test_dir "tmp/test_integration"

  setup do
    # Clean and create test directory
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)

    # Start dependencies (if not already started)
    start_supervised({NbTs.Registry, []}, restart: :temporary)
    start_supervised({NbTs.DependencyTracker, []}, restart: :temporary)

    on_exit(fn ->
      File.rm_rf!(@test_dir)
    end)

    {:ok, output_dir: @test_dir}
  end

  describe "real-world serializer metadata format" do
    test "generates TypeScript for Product serializer with all field types", %{output_dir: dir} do
      # Simulate a realistic NbSerializer metadata format
      defmodule ProductSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            # Basic types
            id: %{type: :integer, optional: false, nullable: false},
            title: %{type: :string, optional: false, nullable: false},
            price: %{type: :number, optional: false, nullable: false},
            available: %{type: :boolean, optional: false, nullable: false},

            # Optional and nullable
            description: %{type: :string, optional: true, nullable: false},
            sale_price: %{type: :number, optional: false, nullable: true},

            # List of primitives
            tags: %{type: :string, list: true, optional: false, nullable: false},

            # Enum
            status: %{enum: ["active", "draft", "archived"], optional: false, nullable: false},

            # List of enums (new unified syntax)
            availability: %{
              list: [enum: ["in_stock", "out_of_stock", "preorder"]],
              optional: true,
              nullable: false
            },

            # Custom metadata
            metadata: %{type: :any, optional: true, nullable: true}
          }
        end
      end

      ProductSerializer.__nb_serializer_ensure_registered__()

      # Generate TypeScript
      {:ok, _results} =
        Generator.generate_incremental(
          serializers: [ProductSerializer],
          controllers: [],
          shared_props: [],
          output_dir: dir
        )

      # Read generated file
      typescript_file = Path.join(dir, "ProductSerializer.ts")
      assert File.exists?(typescript_file)

      typescript = File.read!(typescript_file)

      # Verify interface declaration
      assert typescript =~ "export interface Product"

      # Verify basic types (camelized)
      assert typescript =~ "id: number;"
      assert typescript =~ "title: string;"
      assert typescript =~ "price: number;"
      assert typescript =~ "available: boolean;"

      # Verify optional and nullable
      assert typescript =~ "description?: string;"
      assert typescript =~ "salePrice: number | null;"

      # Verify list of primitives
      assert typescript =~ "tags: Array<string>;"

      # Verify enum
      assert typescript =~ ~s(status: "active" | "draft" | "archived";)

      # Verify list of enums
      assert typescript =~ "availability?: (\"in_stock\" | \"out_of_stock\" | \"preorder\")[];"

      # Verify any type
      assert typescript =~ "metadata?: any | null;"
    end

    test "generates TypeScript for nested serializers", %{output_dir: dir} do
      # Define nested serializer
      defmodule ImageSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            url: %{type: :string, optional: false, nullable: false},
            width: %{type: :integer, optional: true, nullable: false},
            height: %{type: :integer, optional: true, nullable: false}
          }
        end
      end

      # Define parent serializer with relationship
      defmodule VariantSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            id: %{type: :integer, optional: false, nullable: false},
            sku: %{type: :string, optional: false, nullable: false},
            image: %{serializer: ImageSerializer, optional: true, nullable: false},
            images: %{serializer: ImageSerializer, list: true, optional: false, nullable: false}
          }
        end
      end

      ImageSerializer.__nb_serializer_ensure_registered__()
      VariantSerializer.__nb_serializer_ensure_registered__()

      # Generate TypeScript
      {:ok, _results} =
        Generator.generate_incremental(
          serializers: [ImageSerializer, VariantSerializer],
          controllers: [],
          shared_props: [],
          output_dir: dir
        )

      # Read generated files
      image_typescript = File.read!(Path.join(dir, "ImageSerializer.ts"))
      variant_typescript = File.read!(Path.join(dir, "VariantSerializer.ts"))

      # Verify Image interface
      assert image_typescript =~ "export interface Image"
      assert image_typescript =~ "url: string;"
      assert image_typescript =~ "width?: number;"
      assert image_typescript =~ "height?: number;"

      # Verify Variant interface with relationships
      assert variant_typescript =~ "export interface Variant"
      assert variant_typescript =~ ~s(import type { Image } from "./ImageSerializer";)
      assert variant_typescript =~ "image?: Image;"
      assert variant_typescript =~ "images: Array<Image>;"
    end

    test "generates correct index.ts with all exports", %{output_dir: dir} do
      defmodule UserSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            id: %{type: :integer, optional: false, nullable: false},
            email: %{type: :string, optional: false, nullable: false}
          }
        end
      end

      defmodule PostSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            id: %{type: :integer, optional: false, nullable: false},
            title: %{type: :string, optional: false, nullable: false}
          }
        end
      end

      UserSerializer.__nb_serializer_ensure_registered__()
      PostSerializer.__nb_serializer_ensure_registered__()

      # Generate TypeScript
      {:ok, _results} =
        Generator.generate_incremental(
          serializers: [UserSerializer, PostSerializer],
          controllers: [],
          shared_props: [],
          output_dir: dir
        )

      # Read index file
      index_typescript = File.read!(Path.join(dir, "index.ts"))

      # Verify exports are alphabetically sorted
      assert index_typescript =~ ~s(export type { Post } from "./PostSerializer";)
      assert index_typescript =~ ~s(export type { User } from "./UserSerializer";)
    end
  end

  describe "edge cases" do
    test "handles serializer with only enum fields", %{output_dir: dir} do
      defmodule StatusSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            primary: %{enum: ["pending", "active", "inactive"], optional: false, nullable: false},
            secondary: %{
              list: [enum: ["verified", "unverified"]],
              optional: true,
              nullable: false
            }
          }
        end
      end

      StatusSerializer.__nb_serializer_ensure_registered__()

      {:ok, _results} =
        Generator.generate_incremental(
          serializers: [StatusSerializer],
          controllers: [],
          shared_props: [],
          output_dir: dir
        )

      typescript = File.read!(Path.join(dir, "StatusSerializer.ts"))

      assert typescript =~ "export interface Status"
      assert typescript =~ ~s(primary: "pending" | "active" | "inactive";)
      assert typescript =~ "secondary?: (\"verified\" | \"unverified\")[];"
    end

    test "handles empty serializer", %{output_dir: dir} do
      defmodule EmptySerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{}
        end
      end

      EmptySerializer.__nb_serializer_ensure_registered__()

      {:ok, _results} =
        Generator.generate_incremental(
          serializers: [EmptySerializer],
          controllers: [],
          shared_props: [],
          output_dir: dir
        )

      typescript = File.read!(Path.join(dir, "EmptySerializer.ts"))

      # Should generate valid empty interface
      assert typescript =~ "export interface Empty"
      assert typescript =~ "export interface Empty {\n\n}"
    end
  end

  describe "Inertia declarations" do
    test "generates inertia.d.ts when Inertia pages are present", %{output_dir: dir} do
      # Define a minimal controller with an Inertia page
      defmodule TestInertiaController do
        def __inertia_pages__ do
          %{
            index: %{
              component: "Test/Index",
              props: [
                %{name: :message, type: :string, opts: []}
              ]
            }
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Generate TypeScript
      {:ok, _results} =
        Generator.generate_incremental(
          serializers: [],
          controllers: [TestInertiaController],
          shared_props: [],
          output_dir: dir
        )

      # Verify inertia.d.ts was generated
      inertia_file = Path.join(dir, "inertia.d.ts")
      assert File.exists?(inertia_file)

      inertia_content = File.read!(inertia_file)

      # Verify RouteResult type is defined
      assert inertia_content =~ "export type RouteResult"
      assert inertia_content =~ "url: string"
      assert inertia_content =~ "method: 'get' | 'post' | 'put' | 'patch' | 'delete' | 'head'"

      # Verify Href type alias is defined
      assert inertia_content =~ "export type Href = string | RouteResult"

      # Verify module augmentation for @inertiajs/react
      assert inertia_content =~ "declare module '@inertiajs/react'"
      assert inertia_content =~ "interface InertiaLinkProps"
      assert inertia_content =~ "href: string | RouteResult"
      assert inertia_content =~ "interface Router"
      assert inertia_content =~ "visit(href: string | RouteResult"

      # Verify index.ts includes inertia exports
      # The index manager now auto-exports all types from .ts files,
      # so RouteResult and Href should be exported from inertia.d.ts
      index_file = Path.join(dir, "index.ts")
      assert File.exists?(index_file)

      index_content = File.read!(index_file)
      # RouteResult and Href are exported (may be grouped or separate)
      assert index_content =~ "RouteResult"
      assert index_content =~ "Href"
      assert index_content =~ ~s(from "./inertia")
    end

    test "does not generate inertia.d.ts when no Inertia pages are present", %{output_dir: dir} do
      # Define a simple serializer
      defmodule SimpleSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)

        def __nb_serializer_type_metadata__ do
          %{
            id: %{type: :integer, optional: false, nullable: false}
          }
        end
      end

      SimpleSerializer.__nb_serializer_ensure_registered__()

      # Generate TypeScript without any controllers
      {:ok, _results} =
        Generator.generate_incremental(
          serializers: [SimpleSerializer],
          controllers: [],
          shared_props: [],
          output_dir: dir
        )

      # Verify inertia.d.ts was NOT generated
      inertia_file = Path.join(dir, "inertia.d.ts")
      refute File.exists?(inertia_file)

      # Verify index.ts does not include inertia exports
      index_file = Path.join(dir, "index.ts")
      index_content = File.read!(index_file)
      refute index_content =~ "RouteResult"
      refute index_content =~ "Href"
    end
  end
end
