defmodule NbTs.DependencyTrackerTest do
  use ExUnit.Case, async: false

  alias NbTs.DependencyTracker

  setup do
    # Clear the ETS table before each test (tracker is already started by application)
    # If it's not started (e.g., in some test environments), start it
    case Process.whereis(DependencyTracker) do
      nil -> start_supervised(DependencyTracker)
      _pid -> :ok
    end

    # Clear all dependencies before each test
    try do
      :ets.delete_all_objects(:nb_ts_dependencies)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  describe "add_dependency/2" do
    test "records a dependency between file and module" do
      assert :ok = DependencyTracker.add_dependency("UsersIndexProps.ts", MyApp.UserSerializer)

      dependents = DependencyTracker.get_dependents(MyApp.UserSerializer)
      assert "UsersIndexProps.ts" in dependents
    end

    test "records multiple dependencies for same file" do
      :ok = DependencyTracker.add_dependency("UsersIndexProps.ts", MyApp.UserSerializer)
      :ok = DependencyTracker.add_dependency("UsersIndexProps.ts", MyApp.AuthSharedProps)

      assert "UsersIndexProps.ts" in DependencyTracker.get_dependents(MyApp.UserSerializer)
      assert "UsersIndexProps.ts" in DependencyTracker.get_dependents(MyApp.AuthSharedProps)
    end

    test "allows multiple files to depend on same module" do
      :ok = DependencyTracker.add_dependency("UsersIndexProps.ts", MyApp.UserSerializer)
      :ok = DependencyTracker.add_dependency("UsersShowProps.ts", MyApp.UserSerializer)

      dependents = DependencyTracker.get_dependents(MyApp.UserSerializer)
      assert "UsersIndexProps.ts" in dependents
      assert "UsersShowProps.ts" in dependents
    end

    test "works when tracker is not started" do
      # Note: Tracker is started by application, so we can't easily stop it
      # This test verifies the graceful handling in the function itself
      # Should not crash even if called with non-existent tracker
      assert :ok = DependencyTracker.add_dependency("File.ts", MyApp.Module)
    end
  end

  describe "get_dependents/1" do
    test "returns empty list when module has no dependents" do
      assert [] = DependencyTracker.get_dependents(NonExistent.Module)
    end

    test "returns list of files that depend on module" do
      DependencyTracker.add_dependency("File1.ts", MyApp.UserSerializer)
      DependencyTracker.add_dependency("File2.ts", MyApp.UserSerializer)
      DependencyTracker.add_dependency("File3.ts", MyApp.PostSerializer)

      dependents = DependencyTracker.get_dependents(MyApp.UserSerializer)
      assert length(dependents) == 2
      assert "File1.ts" in dependents
      assert "File2.ts" in dependents
      refute "File3.ts" in dependents
    end

    test "returns unique file names even if added multiple times" do
      DependencyTracker.add_dependency("File1.ts", MyApp.UserSerializer)
      DependencyTracker.add_dependency("File1.ts", MyApp.UserSerializer)
      DependencyTracker.add_dependency("File1.ts", MyApp.UserSerializer)

      dependents = DependencyTracker.get_dependents(MyApp.UserSerializer)
      assert dependents == ["File1.ts"]
    end

    test "returns empty list when module has no dependents after clear" do
      # Add and then clear to test empty state
      DependencyTracker.add_dependency("File.ts", MyApp.Module)
      DependencyTracker.clear_dependencies("File.ts")

      assert [] = DependencyTracker.get_dependents(MyApp.Module)
    end
  end

  describe "clear_dependencies/1" do
    test "removes all dependencies for a file" do
      DependencyTracker.add_dependency("File1.ts", MyApp.UserSerializer)
      DependencyTracker.add_dependency("File1.ts", MyApp.PostSerializer)

      assert :ok = DependencyTracker.clear_dependencies("File1.ts")

      assert [] = DependencyTracker.get_dependents(MyApp.UserSerializer)
      assert [] = DependencyTracker.get_dependents(MyApp.PostSerializer)
    end

    test "only clears dependencies for specified file" do
      DependencyTracker.add_dependency("File1.ts", MyApp.UserSerializer)
      DependencyTracker.add_dependency("File2.ts", MyApp.UserSerializer)

      DependencyTracker.clear_dependencies("File1.ts")

      dependents = DependencyTracker.get_dependents(MyApp.UserSerializer)
      assert dependents == ["File2.ts"]
    end

    test "works with non-existent files" do
      # Should not crash when clearing dependencies for files that don't exist
      assert :ok = DependencyTracker.clear_dependencies("NonExistentFile.ts")
    end

    test "allows re-adding dependencies after clearing" do
      DependencyTracker.add_dependency("File1.ts", MyApp.UserSerializer)
      DependencyTracker.clear_dependencies("File1.ts")
      DependencyTracker.add_dependency("File1.ts", MyApp.PostSerializer)

      assert [] = DependencyTracker.get_dependents(MyApp.UserSerializer)
      assert ["File1.ts"] = DependencyTracker.get_dependents(MyApp.PostSerializer)
    end
  end

  describe "dependency_graph/0" do
    test "returns empty map when no dependencies" do
      assert %{} = DependencyTracker.dependency_graph()
    end

    test "returns map of files to their module dependencies" do
      DependencyTracker.add_dependency("File1.ts", MyApp.UserSerializer)
      DependencyTracker.add_dependency("File1.ts", MyApp.PostSerializer)
      DependencyTracker.add_dependency("File2.ts", MyApp.UserSerializer)

      graph = DependencyTracker.dependency_graph()

      assert is_map(graph)
      assert MyApp.UserSerializer in graph["File1.ts"]
      assert MyApp.PostSerializer in graph["File1.ts"]
      assert MyApp.UserSerializer in graph["File2.ts"]
    end

    test "returns empty map when no dependencies exist" do
      # Clear any existing dependencies
      try do
        :ets.delete_all_objects(:nb_ts_dependencies)
      rescue
        _ -> :ok
      end

      assert %{} = DependencyTracker.dependency_graph()
    end
  end

  describe "cascade dependencies" do
    test "tracks transitive dependencies correctly" do
      # UsersIndexProps depends on UserSerializer
      DependencyTracker.add_dependency("UsersIndexProps.ts", MyApp.UserSerializer)

      # UsersIndexProps also depends on AuthSharedProps
      DependencyTracker.add_dependency("UsersIndexProps.ts", MyApp.AuthSharedProps)

      # PostsIndexProps depends on UserSerializer too
      DependencyTracker.add_dependency("PostsIndexProps.ts", MyApp.UserSerializer)

      # When UserSerializer changes, both props files need regeneration
      user_dependents = DependencyTracker.get_dependents(MyApp.UserSerializer)
      assert length(user_dependents) == 2
      assert "UsersIndexProps.ts" in user_dependents
      assert "PostsIndexProps.ts" in user_dependents

      # When AuthSharedProps changes, only UsersIndexProps needs regeneration
      auth_dependents = DependencyTracker.get_dependents(MyApp.AuthSharedProps)
      assert auth_dependents == ["UsersIndexProps.ts"]
    end
  end

  describe "concurrent access" do
    test "handles concurrent dependency additions" do
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            DependencyTracker.add_dependency(
              "File#{rem(i, 10)}.ts",
              Module.concat([MyApp, "Serializer#{i}"])
            )
          end)
        end

      Enum.each(tasks, &Task.await/1)

      # Should have created dependencies without crashing
      graph = DependencyTracker.dependency_graph()
      assert map_size(graph) > 0
    end

    test "handles concurrent reads and writes" do
      # Seed some data
      DependencyTracker.add_dependency("File1.ts", MyApp.Serializer)

      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            if rem(i, 2) == 0 do
              DependencyTracker.add_dependency("File#{i}.ts", MyApp.Serializer)
            else
              DependencyTracker.get_dependents(MyApp.Serializer)
            end
          end)
        end

      results = Enum.map(tasks, &Task.await/1)

      # All reads should have returned lists
      read_results = Enum.filter(results, &is_list/1)
      assert length(read_results) > 0
      assert Enum.all?(read_results, fn list -> is_list(list) and length(list) > 0 end)
    end
  end
end
