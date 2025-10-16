defmodule NbTs.IndexManagerTest do
  use ExUnit.Case, async: true

  alias NbTs.IndexManager

  @test_dir "tmp/test_index_manager"

  setup do
    # Clean and create test directory
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)

    on_exit(fn ->
      File.rm_rf!(@test_dir)
    end)

    {:ok, output_dir: @test_dir}
  end

  describe "update_index/2" do
    test "creates new index.ts with added entries", %{output_dir: dir} do
      entries = [
        {"User", "User"},
        {"Post", "Post"}
      ]

      assert {:ok, 2} = IndexManager.update_index(dir, added: entries)

      index_path = Path.join(dir, "index.ts")
      assert File.exists?(index_path)

      content = File.read!(index_path)
      assert content =~ ~s(export type { User } from "./User";)
      assert content =~ ~s(export type { Post } from "./Post";)
    end

    test "appends new entries to existing index", %{output_dir: dir} do
      # Create initial index
      {:ok, _} = IndexManager.update_index(dir, added: [{"User", "User"}])

      # Add more entries
      {:ok, 2} = IndexManager.update_index(dir, added: [{"Post", "Post"}])

      content = File.read!(Path.join(dir, "index.ts"))
      assert content =~ ~s(export type { User } from "./User";)
      assert content =~ ~s(export type { Post } from "./Post";)
    end

    test "removes entries from index", %{output_dir: dir} do
      # Create initial index
      {:ok, _} = IndexManager.update_index(dir, added: [{"User", "User"}, {"Post", "Post"}])

      # Remove one entry
      {:ok, 1} = IndexManager.update_index(dir, removed: ["Post"])

      content = File.read!(Path.join(dir, "index.ts"))
      assert content =~ ~s(export type { User } from "./User";)
      refute content =~ "Post"
    end

    test "updates existing entries", %{output_dir: dir} do
      # Create initial index
      {:ok, _} = IndexManager.update_index(dir, added: [{"User", "User"}])

      # Update with different filename
      {:ok, 1} = IndexManager.update_index(dir, updated: [{"User", "UserV2"}])

      content = File.read!(Path.join(dir, "index.ts"))
      assert content =~ ~s(export type { User } from "./UserV2";)
      refute content =~ ~s("./User")
    end

    test "sorts entries alphabetically", %{output_dir: dir} do
      entries = [
        {"Zebra", "Zebra"},
        {"Apple", "Apple"},
        {"Mango", "Mango"}
      ]

      {:ok, _} = IndexManager.update_index(dir, added: entries)

      content = File.read!(Path.join(dir, "index.ts"))
      lines = String.split(content, "\n", trim: true)

      assert Enum.at(lines, 0) =~ "Apple"
      assert Enum.at(lines, 1) =~ "Mango"
      assert Enum.at(lines, 2) =~ "Zebra"
    end

    test "handles multiple operations at once", %{output_dir: dir} do
      # Create initial index
      {:ok, _} =
        IndexManager.update_index(dir,
          added: [{"User", "User"}, {"Post", "Post"}, {"Old", "Old"}]
        )

      # Add, remove, and update in one call
      {:ok, 3} =
        IndexManager.update_index(dir,
          added: [{"Comment", "Comment"}],
          removed: ["Old"],
          updated: [{"User", "UserV2"}]
        )

      content = File.read!(Path.join(dir, "index.ts"))
      assert content =~ ~s(export type { Comment } from "./Comment";)
      assert content =~ ~s(export type { Post } from "./Post";)
      assert content =~ ~s(export type { User } from "./UserV2";)
      refute content =~ "Old"
    end

    test "returns count of final entries", %{output_dir: dir} do
      assert {:ok, 2} = IndexManager.update_index(dir, added: [{"A", "A"}, {"B", "B"}])
      assert {:ok, 3} = IndexManager.update_index(dir, added: [{"C", "C"}])
      assert {:ok, 2} = IndexManager.update_index(dir, removed: ["A"])
    end

    test "handles empty operations", %{output_dir: dir} do
      {:ok, _} = IndexManager.update_index(dir, added: [{"User", "User"}])
      assert {:ok, 1} = IndexManager.update_index(dir, added: [], removed: [], updated: [])
    end
  end

  describe "rebuild_index/1" do
    test "scans directory and rebuilds index from .ts files", %{output_dir: dir} do
      # Create some .ts files
      File.write!(Path.join(dir, "User.ts"), "export interface User { id: number; }")
      File.write!(Path.join(dir, "Post.ts"), "export interface Post { id: number; }")
      File.write!(Path.join(dir, "Comment.ts"), "export interface Comment { id: number; }")

      assert {:ok, 3} = IndexManager.rebuild_index(dir)

      content = File.read!(Path.join(dir, "index.ts"))
      assert content =~ ~s(export type { User } from "./User";)
      assert content =~ ~s(export type { Post } from "./Post";)
      assert content =~ ~s(export type { Comment } from "./Comment";)
    end

    test "excludes index.ts itself", %{output_dir: dir} do
      # Create files including an existing index
      File.write!(Path.join(dir, "User.ts"), "export interface User {}")
      File.write!(Path.join(dir, "index.ts"), "old content")

      {:ok, _} = IndexManager.rebuild_index(dir)

      content = File.read!(Path.join(dir, "index.ts"))
      assert content =~ "User"
      refute content =~ "index"
    end

    test "handles empty directory", %{output_dir: dir} do
      assert {:ok, 0} = IndexManager.rebuild_index(dir)

      content = File.read!(Path.join(dir, "index.ts"))
      assert content == "\n"
    end

    test "handles directory with no .ts files", %{output_dir: dir} do
      File.write!(Path.join(dir, "readme.md"), "docs")

      assert {:ok, 0} = IndexManager.rebuild_index(dir)
    end
  end

  describe "parse_export_line/1" do
    test "parses valid export line" do
      line = ~s(export type { User } from "./User";)
      assert [{"User", "User"}] = IndexManager.parse_export_line(line)
    end

    test "returns empty list for invalid line" do
      assert [] = IndexManager.parse_export_line("import { User } from './User'")
      assert [] = IndexManager.parse_export_line("// comment")
      assert [] = IndexManager.parse_export_line("")
    end

    test "handles different path formats" do
      line1 = ~s(export type { User } from "./User";)
      line2 = ~s(export type { User } from "./subdirectory/User";)

      assert [{"User", "User"}] = IndexManager.parse_export_line(line1)
      assert [{"User", "subdirectory/User"}] = IndexManager.parse_export_line(line2)
    end
  end
end
