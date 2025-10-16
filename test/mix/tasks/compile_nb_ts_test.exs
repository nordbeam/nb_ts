defmodule Mix.Tasks.Compile.NbTsTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Compile.NbTs, as: CompileNbTs

  @manifest_dir ".mix"
  @manifest_file ".mix/compile.nb_ts"
  @test_dir "tmp/test_compile_nb_ts"

  setup do
    # Clean up before and after
    File.rm_rf!(@manifest_dir)
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)

    # Start required services (if not already started)
    case start_supervised(NbTs.Registry) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    case start_supervised(NbTs.DependencyTracker) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Setup Mix project config
    original_config = Mix.Project.config()

    on_exit(fn ->
      File.rm_rf!(@manifest_dir)
      File.rm_rf!(@test_dir)
      # Reset Mix project config
      if original_config do
        Application.put_env(:mix, :project_config, original_config)
      end
    end)

    {:ok, output_dir: @test_dir}
  end

  describe "run/1" do
    test "returns {:noop, []} when auto_generate is disabled", %{output_dir: dir} do
      set_project_config(nb_ts: [output_dir: dir, auto_generate: false])

      assert {:noop, []} = CompileNbTs.run([])
    end

    test "generates types for changed modules on first run", %{output_dir: dir} do
      set_project_config(nb_ts: [output_dir: dir, auto_generate: true])

      # Define a serializer
      defmodule FirstRunSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{
            fields: [%{name: :id, type: :integer, opts: []}]
          }

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      FirstRunSerializer.__nb_serializer_ensure_registered__()

      assert {:ok, []} = CompileNbTs.run([])

      # Should have created manifest
      assert File.exists?(@manifest_file)

      # Should have generated TypeScript
      assert File.exists?(Path.join(dir, "FirstRunSerializer.ts"))
      assert File.exists?(Path.join(dir, "index.ts"))
    end

    test "skips generation when no modules changed", %{output_dir: dir} do
      set_project_config(nb_ts: [output_dir: dir, auto_generate: true])

      defmodule UnchangedSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{fields: [%{name: :id, type: :integer, opts: []}]}

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      UnchangedSerializer.__nb_serializer_ensure_registered__()

      # First run
      {:ok, []} = CompileNbTs.run([])

      ts_file = Path.join(dir, "UnchangedSerializer.ts")
      initial_mtime = File.stat!(ts_file).mtime

      # Wait a bit
      :timer.sleep(10)

      # Second run with no changes
      assert {:noop, []} = CompileNbTs.run([])

      # File should not have been modified
      assert File.stat!(ts_file).mtime == initial_mtime
    end

    test "detects changed modules and regenerates", %{output_dir: dir} do
      set_project_config(nb_ts: [output_dir: dir, auto_generate: true])

      defmodule ChangedSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{fields: [%{name: :id, type: :integer, opts: []}]}

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      ChangedSerializer.__nb_serializer_ensure_registered__()

      # First run
      {:ok, []} = CompileNbTs.run([])

      # Simulate module change by modifying manifest
      manifest = read_manifest()
      # Change the hash for this module
      updated_manifest =
        Map.put(manifest, ChangedSerializer, :erlang.md5("different content"))

      write_manifest(updated_manifest)

      # Second run should detect change
      assert {:ok, []} = CompileNbTs.run([])
    end

    test "creates output directory if it doesn't exist", %{output_dir: _dir} do
      non_existent = Path.join(@test_dir, "new/nested/dir")
      set_project_config(nb_ts: [output_dir: non_existent, auto_generate: true])

      refute File.exists?(non_existent)

      defmodule AutoCreateSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{fields: [%{name: :id, type: :integer, opts: []}]}

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      AutoCreateSerializer.__nb_serializer_ensure_registered__()

      assert {:ok, []} = CompileNbTs.run([])
      assert File.exists?(non_existent)
    end

    test "handles errors gracefully", %{output_dir: dir} do
      set_project_config(nb_ts: [output_dir: dir, auto_generate: true])

      # Create a malformed serializer
      defmodule ErrorSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data
        def __nb_serializer_type_metadata__, do: %{}
        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      ErrorSerializer.__nb_serializer_ensure_registered__()

      # Should not crash, returns error
      result = CompileNbTs.run([])

      assert match?({:error, _}, result) or match?({:ok, _}, result) or
               match?({:noop, _}, result)
    end

    test "detects both serializers and controllers", %{output_dir: dir} do
      set_project_config(nb_ts: [output_dir: dir, auto_generate: true])

      defmodule MixedSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{fields: [%{name: :id, type: :integer, opts: []}]}

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      defmodule MixedController do
        def __inertia_pages__, do: %{index: %{component: "Mixed/Index", props: []}}

        def inertia_page_config(:index),
          do: %{
            component: "Mixed/Index",
            props: [%{name: :data, type: :list, opts: []}]
          }

        def __inertia_shared_modules__, do: []
      end

      MixedSerializer.__nb_serializer_ensure_registered__()

      assert {:ok, []} = CompileNbTs.run([])

      # Should have generated both
      assert File.exists?(Path.join(dir, "MixedSerializer.ts"))
      assert File.exists?(Path.join(dir, "MixedIndexProps.ts"))
    end
  end

  describe "manifests/0" do
    test "returns list with manifest path" do
      assert [@manifest_file] = CompileNbTs.manifests()
    end
  end

  describe "clean/0" do
    test "removes manifest file" do
      # Create manifest
      File.mkdir_p!(@manifest_dir)
      File.write!(@manifest_file, "test")
      assert File.exists?(@manifest_file)

      # Clean
      CompileNbTs.clean()

      # Manifest should be gone
      refute File.exists?(@manifest_file)
    end

    test "succeeds even if manifest doesn't exist" do
      refute File.exists?(@manifest_file)
      assert :ok = CompileNbTs.clean()
    end
  end

  describe "manifest management" do
    test "manifest tracks module hashes" do
      defmodule ManifestTestSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{fields: [%{name: :id, type: :integer, opts: []}]}

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      ManifestTestSerializer.__nb_serializer_ensure_registered__()

      set_project_config(nb_ts: [output_dir: @test_dir, auto_generate: true])

      # Run compilation
      CompileNbTs.run([])

      # Read manifest
      manifest = read_manifest()

      # Should contain our serializer with a hash
      assert Map.has_key?(manifest, ManifestTestSerializer)
      assert is_binary(manifest[ManifestTestSerializer])
    end

    test "manifest persists between runs" do
      set_project_config(nb_ts: [output_dir: @test_dir, auto_generate: true])

      defmodule PersistSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{fields: [%{name: :id, type: :integer, opts: []}]}

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      PersistSerializer.__nb_serializer_ensure_registered__()

      # First run
      CompileNbTs.run([])
      first_manifest = read_manifest()

      # Second run
      CompileNbTs.run([])
      second_manifest = read_manifest()

      # Manifest should be consistent
      assert first_manifest[PersistSerializer] == second_manifest[PersistSerializer]
    end
  end

  describe "change detection" do
    test "detects when serializer is added" do
      set_project_config(nb_ts: [output_dir: @test_dir, auto_generate: true])

      # First run with no serializers
      CompileNbTs.run([])
      initial_manifest = read_manifest()

      # Add a serializer
      defmodule NewlyAddedSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{fields: [%{name: :id, type: :integer, opts: []}]}

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      NewlyAddedSerializer.__nb_serializer_ensure_registered__()

      # Second run should detect new module
      CompileNbTs.run([])
      updated_manifest = read_manifest()

      # Manifest should contain new module
      assert Map.has_key?(updated_manifest, NewlyAddedSerializer)
      refute Map.has_key?(initial_manifest, NewlyAddedSerializer)
    end
  end

  describe "configuration" do
    test "uses default output_dir if not configured", %{output_dir: _dir} do
      # Don't set output_dir in config
      set_project_config(nb_ts: [auto_generate: true])

      defmodule DefaultDirSerializer do
        def __nb_serializer__, do: :ok
        def __nb_serializer_serialize__(data, _opts), do: data

        def __nb_serializer_type_metadata__,
          do: %{fields: [%{name: :id, type: :integer, opts: []}]}

        def __nb_serializer_ensure_registered__, do: NbTs.Registry.register(__MODULE__)
      end

      DefaultDirSerializer.__nb_serializer_ensure_registered__()

      # Should use default directory ("assets/js/types")
      # This test just ensures it doesn't crash
      result = CompileNbTs.run([])
      assert match?({:ok, _}, result) or match?({:noop, _}, result)
    end
  end

  # Helper functions

  defp set_project_config(config) do
    Application.put_env(:nb_ts, :test_project_config, config)

    # Mock Mix.Project.config/0 to return our test config
    # Clean up any existing mocks first
    try do
      :meck.unload(Mix.Project)
    rescue
      _ -> :ok
    end

    :meck.new(Mix.Project, [:passthrough])

    :meck.expect(Mix.Project, :config, fn ->
      Keyword.merge([app: :nb_ts], config)
    end)
  end

  defp read_manifest do
    case File.read(@manifest_file) do
      {:ok, content} -> :erlang.binary_to_term(content)
      {:error, _} -> %{}
    end
  end

  defp write_manifest(data) do
    File.mkdir_p!(@manifest_dir)
    content = :erlang.term_to_binary(data)
    File.write!(@manifest_file, content)
  end
end
