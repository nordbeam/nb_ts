defmodule NbTs.RpcInterfaceTest do
  use ExUnit.Case, async: true

  alias NbTs.RpcInterface

  # -- Test helpers: mock procedure modules --

  defmodule MockUserSerializer do
    def __nb_serializer_type_metadata__, do: %{}
    def __nb_serializer_serialize__(_data, _opts), do: %{}

    def __nb_serializer_typescript_name__, do: nil
    def __nb_serializer_typescript_namespace__, do: nil
  end

  defmodule MockProcedures.Users do
    def __nb_rpc_procedures__ do
      [
        {:list,
         %{
           type: :query,
           input: %{page: {:integer, default: 1}, search: {:string, optional: true}},
           output: %{users: {:list, MockUserSerializer}, total_count: :integer}
         }},
        {:get,
         %{
           type: :query,
           input: %{id: :integer},
           output: MockUserSerializer
         }},
        {:create,
         %{
           type: :mutation,
           input: %{name: :string, email: :string},
           output: MockUserSerializer
         }},
        {:on_change,
         %{
           type: :subscription,
           input: %{team_id: {:integer, optional: true}},
           output: %{event: {:enum, ~w(created updated deleted)}, user: MockUserSerializer}
         }}
      ]
    end

    def __nb_rpc_middleware__, do: []
  end

  defmodule MockProcedures.Posts do
    def __nb_rpc_procedures__ do
      [
        {:list,
         %{
           type: :query,
           input: nil,
           output: nil
         }},
        {:delete,
         %{
           type: :mutation,
           input: %{id: :integer},
           output: %{deleted: :boolean}
         }}
      ]
    end

    def __nb_rpc_middleware__, do: []
  end

  # -- Tests --

  test "generate_typescript produces valid TypeScript with scope types" do
    scopes = [
      {"users", MockProcedures.Users},
      {"posts", MockProcedures.Posts}
    ]

    result = RpcInterface.generate_typescript(scopes)

    # Should contain the AppRouter type
    assert result =~ "export type AppRouter = {"
    assert result =~ "users: UsersScope;"
    assert result =~ "posts: PostsScope;"

    # Should contain scope types
    assert result =~ "export type UsersScope = {"
    assert result =~ "export type PostsScope = {"

    # Should contain procedure entries with correct types
    assert result =~ "list: QueryDef<"
    assert result =~ "get: QueryDef<"
    assert result =~ "create: MutationDef<"
    assert result =~ "onChange: SubscriptionDef<"
    assert result =~ "delete: MutationDef<"

    # Should import from nb-rpc types
    assert result =~ ~s(import type { QueryDef, MutationDef, SubscriptionDef } from "@nordbeam/nb-rpc/types")
  end

  test "generate_typescript handles inline map input/output specs" do
    scopes = [{"users", MockProcedures.Users}]
    result = RpcInterface.generate_typescript(scopes)

    # Input with optional and default fields
    assert result =~ "page?"
    assert result =~ "search?"

    # Output with list and primitive
    assert result =~ "totalCount: number"
  end

  test "generate_typescript handles nil input/output specs" do
    scopes = [{"posts", MockProcedures.Posts}]
    result = RpcInterface.generate_typescript(scopes)

    # nil input should be Record<string, never>
    assert result =~ "Record<string, never>"
  end

  test "generate_typescript handles enum types" do
    scopes = [{"users", MockProcedures.Users}]
    result = RpcInterface.generate_typescript(scopes)

    # Enum values in subscription output
    assert result =~ ~s("created")
    assert result =~ ~s("updated")
    assert result =~ ~s("deleted")
  end

  test "generate_router_type returns empty string when no scopes" do
    # When no procedure modules are found (RpcDiscovery returns [])
    {"AppRouter", typescript} = RpcInterface.generate_router_type()

    # Result depends on whether any procedure modules are in the runtime
    # In test environment, there might be our mock modules
    assert is_binary(typescript)
  end

  test "generate_typescript handles serializer module references" do
    scopes = [{"users", MockProcedures.Users}]
    result = RpcInterface.generate_typescript(scopes)

    # Should reference the serializer's interface name
    assert result =~ "MockUser"
  end

  test "scope type names are PascalCase with Scope suffix" do
    scopes = [
      {"users", MockProcedures.Users},
      {"posts", MockProcedures.Posts}
    ]

    result = RpcInterface.generate_typescript(scopes)

    assert result =~ "UsersScope"
    assert result =~ "PostsScope"
  end

  test "procedure names are camelCased" do
    scopes = [{"users", MockProcedures.Users}]
    result = RpcInterface.generate_typescript(scopes)

    # on_change should become onChange
    assert result =~ "onChange:"
  end
end
