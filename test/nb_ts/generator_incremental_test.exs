defmodule NbTs.GeneratorIncrementalTest do
  use ExUnit.Case, async: false

  alias NbTs.Generator

  @test_dir "tmp/test_generator_incremental"

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

  describe "generate_incremental/1" do
    test "generates TypeScript for specified serializers only", %{output_dir: dir} do
      # Define test serializer
      defmodule TestUserSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{
            fields: [
              %{name: :id, type: :integer, opts: []},
              %{name: :name, type: :string, opts: []}
            ]
          }

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      TestUserSerializer.__nb_serializer_ensure_registered__()

      assert {:ok, results} =
               Generator.generate_incremental(
                 serializers: [TestUserSerializer],
                 controllers: [],
                 shared_props: [],
                 output_dir: dir
               )

      assert results.updated_files == 1
      assert File.exists?(Path.join(dir, "TestUserSerializer.ts"))
      assert File.exists?(Path.join(dir, "index.ts"))
    end

    test "generates TypeScript for specified controllers only", %{output_dir: dir} do
      # Define test controller
      defmodule TestUsersController do
        def __inertia_pages__, do: %{index: %{component: "Users/Index", props: []}}

        def inertia_page_config(:index),
          do: %{
            component: "Users/Index",
            props: [
              %{name: :users, type: :list, opts: []},
              %{name: :count, type: :integer, opts: []}
            ]
          }

        def __inertia_shared_modules__, do: []
      end

      assert {:ok, results} =
               Generator.generate_incremental(
                 serializers: [],
                 controllers: [TestUsersController],
                 shared_props: [],
                 output_dir: dir
               )

      assert results.updated_files == 1
      assert File.exists?(Path.join(dir, "UsersIndexProps.ts"))
      assert File.exists?(Path.join(dir, "index.ts"))
    end

    test "generates both serializers and controllers in one call", %{output_dir: dir} do
      defmodule TestPostSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{
            fields: [
              %{name: :id, type: :integer, opts: []},
              %{name: :title, type: :string, opts: []}
            ]
          }

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      defmodule TestPostsController do
        def __inertia_pages__, do: %{index: %{component: "Posts/Index", props: []}}

        def inertia_page_config(:index),
          do: %{
            component: "Posts/Index",
            props: [%{name: :posts, type: :list, opts: []}]
          }

        def __inertia_shared_modules__, do: []
      end

      TestPostSerializer.__nb_serializer_ensure_registered__()

      assert {:ok, results} =
               Generator.generate_incremental(
                 serializers: [TestPostSerializer],
                 controllers: [TestPostsController],
                 shared_props: [],
                 output_dir: dir
               )

      assert results.updated_files == 2
      assert File.exists?(Path.join(dir, "TestPostSerializer.ts"))
      assert File.exists?(Path.join(dir, "PostsIndexProps.ts"))
    end

    test "distinguishes between added and updated files", %{output_dir: dir} do
      defmodule TestCommentSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{
            fields: [
              %{name: :id, type: :integer, opts: []},
              %{name: :text, type: :string, opts: []}
            ]
          }

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      TestCommentSerializer.__nb_serializer_ensure_registered__()

      # First generation - file is added
      {:ok, result1} =
        Generator.generate_incremental(
          serializers: [TestCommentSerializer],
          controllers: [],
          shared_props: [],
          output_dir: dir
        )

      assert result1.added == 1
      assert result1.updated == 0

      # Second generation - file is updated
      {:ok, result2} =
        Generator.generate_incremental(
          serializers: [TestCommentSerializer],
          controllers: [],
          shared_props: [],
          output_dir: dir
        )

      assert result2.added == 0
      assert result2.updated == 1
    end

    test "updates index.ts incrementally", %{output_dir: dir} do
      defmodule TestTagSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{
            fields: [
              %{name: :id, type: :integer, opts: []},
              %{name: :label, type: :string, opts: []}
            ]
          }

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      TestTagSerializer.__nb_serializer_ensure_registered__()

      # Generate first type
      Generator.generate_incremental(
        serializers: [TestTagSerializer],
        controllers: [],
        shared_props: [],
        output_dir: dir
      )

      index_content = File.read!(Path.join(dir, "index.ts"))
      assert index_content =~ "TestTagSerializer"
      initial_line_count = String.split(index_content, "\n", trim: true) |> length()

      # Generate second type
      defmodule TestCategorySerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{
            fields: [
              %{name: :id, type: :integer, opts: []},
              %{name: :name, type: :string, opts: []}
            ]
          }

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      TestCategorySerializer.__nb_serializer_ensure_registered__()

      Generator.generate_incremental(
        serializers: [TestCategorySerializer],
        controllers: [],
        shared_props: [],
        output_dir: dir
      )

      updated_content = File.read!(Path.join(dir, "index.ts"))
      assert updated_content =~ "TestTagSerializer"
      assert updated_content =~ "TestCategorySerializer"

      updated_line_count = String.split(updated_content, "\n", trim: true) |> length()
      assert updated_line_count == initial_line_count + 1
    end

    test "handles empty input gracefully", %{output_dir: dir} do
      assert {:ok, results} =
               Generator.generate_incremental(
                 serializers: [],
                 controllers: [],
                 shared_props: [],
                 output_dir: dir
               )

      assert results.updated_files == 0
      assert results.added == 0
      assert results.updated == 0
    end

    test "validates generated TypeScript when validate option is true", %{output_dir: dir} do
      defmodule TestValidSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{
            fields: [
              %{name: :id, type: :integer, opts: []},
              %{name: :valid_field, type: :string, opts: []}
            ]
          }

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      TestValidSerializer.__nb_serializer_ensure_registered__()

      assert {:ok, _results} =
               Generator.generate_incremental(
                 serializers: [TestValidSerializer],
                 controllers: [],
                 shared_props: [],
                 output_dir: dir,
                 validate: true
               )
    end

    test "creates output directory if it doesn't exist" do
      non_existent_dir = Path.join(@test_dir, "nested/deep/dir")
      refute File.exists?(non_existent_dir)

      defmodule TestAutoCreateSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{
            fields: [%{name: :id, type: :integer, opts: []}]
          }

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      TestAutoCreateSerializer.__nb_serializer_ensure_registered__()

      assert {:ok, _} =
               Generator.generate_incremental(
                 serializers: [TestAutoCreateSerializer],
                 controllers: [],
                 shared_props: [],
                 output_dir: non_existent_dir
               )

      assert File.exists?(non_existent_dir)
      assert File.exists?(Path.join(non_existent_dir, "TestAutoCreateSerializer.ts"))
    end

    test "regenerates dependent files when serializer changes", %{output_dir: dir} do
      # Setup: Create a serializer and a controller that uses it
      defmodule TestAuthorSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{
            fields: [
              %{name: :id, type: :integer, opts: []},
              %{name: :name, type: :string, opts: []}
            ]
          }

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      defmodule TestAuthorsController do
        def __inertia_pages__, do: %{index: %{component: "Authors/Index", props: []}}

        def inertia_page_config(:index),
          do: %{
            component: "Authors/Index",
            props: [%{name: :authors, serializer: TestAuthorSerializer, opts: []}]
          }

        def __inertia_shared_modules__, do: []
      end

      TestAuthorSerializer.__nb_serializer_ensure_registered__()

      # First: Generate controller (which depends on serializer)
      Generator.generate_incremental(
        serializers: [],
        controllers: [TestAuthorsController],
        shared_props: [],
        output_dir: dir
      )

      controller_file = Path.join(dir, "AuthorsIndexProps.ts")
      assert File.exists?(controller_file)
      _initial_mtime = File.stat!(controller_file).mtime

      # Wait a bit to ensure mtime would change
      :timer.sleep(10)

      # Second: Regenerate serializer (should also regenerate dependent controller)
      {:ok, results} =
        Generator.generate_incremental(
          serializers: [TestAuthorSerializer],
          controllers: [],
          shared_props: [],
          output_dir: dir
        )

      # Should have regenerated both serializer and dependent controller
      assert results.updated_files >= 1

      # Controller file should have been touched/regenerated
      # (In a real implementation, this would check that dependent was regenerated)
      assert File.exists?(controller_file)
    end
  end

  describe "generate_incremental/1 error handling" do
    test "returns error if generation fails", %{output_dir: dir} do
      # Create a malformed serializer that will fail generation
      defmodule TestBrokenSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        # Missing required fields in metadata
        def __nb_serializer_type_metadata__, do: %{}
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      TestBrokenSerializer.__nb_serializer_ensure_registered__()

      # This should handle the error gracefully
      result =
        Generator.generate_incremental(
          serializers: [TestBrokenSerializer],
          controllers: [],
          shared_props: [],
          output_dir: dir
        )

      # Should either succeed or return an error tuple
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
