defmodule NbTs.SigilTest do
  use ExUnit.Case, async: false

  import NbTs.Sigil

  describe "~TS sigil - basic types" do
    test "validates simple object type" do
      assert {:typescript_validated, "{ id: number; name: string }"} =
               ~TS"{ id: number; name: string }"
    end

    test "validates primitive types" do
      assert {:typescript_validated, "string"} = ~TS"string"
      assert {:typescript_validated, "number"} = ~TS"number"
      assert {:typescript_validated, "boolean"} = ~TS"boolean"
      assert {:typescript_validated, "null"} = ~TS"null"
      assert {:typescript_validated, "undefined"} = ~TS"undefined"
      assert {:typescript_validated, "any"} = ~TS"any"
      assert {:typescript_validated, "unknown"} = ~TS"unknown"
    end

    test "validates array types" do
      assert {:typescript_validated, "string[]"} = ~TS"string[]"
      assert {:typescript_validated, "number[]"} = ~TS"number[]"
      assert {:typescript_validated, "Array<string>"} = ~TS"Array<string>"
      assert {:typescript_validated, "Array<number>"} = ~TS"Array<number>"
    end

    test "validates union types" do
      assert {:typescript_validated, "string | number"} = ~TS"string | number"
      assert {:typescript_validated, "'active' | 'inactive'"} = ~TS"'active' | 'inactive'"

      assert {:typescript_validated, "'pending' | 'approved' | 'rejected'"} =
               ~TS"'pending' | 'approved' | 'rejected'"
    end

    test "validates tuple types" do
      assert {:typescript_validated, "[string, number]"} = ~TS"[string, number]"
      assert {:typescript_validated, "[number, string, boolean]"} = ~TS"[number, string, boolean]"
    end
  end

  describe "~TS sigil - complex types" do
    test "validates Record types" do
      assert {:typescript_validated, "Record<string, unknown>"} = ~TS"Record<string, unknown>"
      assert {:typescript_validated, "Record<string, any>"} = ~TS"Record<string, any>"
      assert {:typescript_validated, "Record<string, number>"} = ~TS"Record<string, number>"
    end

    test "validates index signatures" do
      assert {:typescript_validated, "{ [key: string]: any }"} = ~TS"{ [key: string]: any }"
      assert {:typescript_validated, "{ [key: string]: number }"} = ~TS"{ [key: string]: number }"
    end

    test "validates nested object types" do
      assert {:typescript_validated, "{ user: { id: number; name: string } }"} =
               ~TS"{ user: { id: number; name: string } }"

      assert {:typescript_validated, "{ data: { items: Array<string> } }"} =
               ~TS"{ data: { items: Array<string> } }"
    end

    test "validates optional properties" do
      assert {:typescript_validated, "{ name?: string }"} = ~TS"{ name?: string }"

      assert {:typescript_validated, "{ id: number; name?: string }"} =
               ~TS"{ id: number; name?: string }"
    end

    test "validates readonly properties" do
      assert {:typescript_validated, "{ readonly id: number }"} = ~TS"{ readonly id: number }"

      assert {:typescript_validated, "{ readonly name: string; age: number }"} =
               ~TS"{ readonly name: string; age: number }"
    end

    test "validates utility types with inline types" do
      assert {:typescript_validated, "Partial<{ name: string; age: number }>"} =
               ~TS"Partial<{ name: string; age: number }>"

      assert {:typescript_validated, "Readonly<{ id: number }>"} = ~TS"Readonly<{ id: number }>"

      assert {:typescript_validated,
              "Pick<{ id: number; name: string; age: number }, 'id' | 'name'>"} =
               ~TS"Pick<{ id: number; name: string; age: number }, 'id' | 'name'>"

      assert {:typescript_validated, "Omit<{ id: number; password: string }, 'password'>"} =
               ~TS"Omit<{ id: number; password: string }, 'password'>"

      assert {:typescript_validated, "Required<{ name?: string; age?: number }>"} =
               ~TS"Required<{ name?: string; age?: number }>"
    end

    test "validates intersection types" do
      assert {:typescript_validated, "{ id: number } & { name: string }"} =
               ~TS"{ id: number } & { name: string }"
    end

    test "validates function types" do
      assert {:typescript_validated, "(x: number) => string"} = ~TS"(x: number) => string"

      assert {:typescript_validated, "(a: number, b: number) => number"} =
               ~TS"(a: number, b: number) => number"
    end

    test "validates generic types" do
      assert {:typescript_validated, "Array<{ id: number }>"} = ~TS"Array<{ id: number }>"
      assert {:typescript_validated, "Array<string | number>"} = ~TS"Array<string | number>"

      assert {:typescript_validated, "Record<string, Array<number>>"} =
               ~TS"Record<string, Array<number>>"
    end
  end

  describe "~TS sigil - real-world patterns" do
    test "validates API response type" do
      assert {:typescript_validated,
              "{ data: any; error: string | null; meta: { timestamp: number } }"} =
               ~TS"{ data: any; error: string | null; meta: { timestamp: number } }"
    end

    test "validates pagination type" do
      assert {:typescript_validated, "{ page: number; total: number; hasNext: boolean }"} =
               ~TS"{ page: number; total: number; hasNext: boolean }"
    end

    test "validates form field type" do
      assert {:typescript_validated, "{ value: string; error?: string; touched: boolean }"} =
               ~TS"{ value: string; error?: string; touched: boolean }"
    end

    test "validates state type with unions" do
      assert {:typescript_validated, "{ status: 'idle' | 'loading' | 'success' | 'error' }"} =
               ~TS"{ status: 'idle' | 'loading' | 'success' | 'error' }"
    end

    test "validates metadata type" do
      assert {:typescript_validated, "Record<string, string | number | boolean>"} =
               ~TS"Record<string, string | number | boolean>"
    end
  end

  describe "~TS sigil - compile-time validation" do
    test "rejects invalid syntax - unclosed brace" do
      assert_raise CompileError, ~r/Invalid TypeScript syntax/, fn ->
        Code.eval_quoted(
          quote do
            import NbTs.Sigil
            ~TS"{ id: number"
          end
        )
      end
    end

    test "rejects invalid syntax - missing colon" do
      assert_raise CompileError, ~r/Invalid TypeScript syntax/, fn ->
        Code.eval_quoted(
          quote do
            import NbTs.Sigil
            ~TS"{ id number }"
          end
        )
      end
    end

    test "rejects type errors - type mismatch" do
      assert_raise CompileError, ~r/Invalid TypeScript syntax|not assignable/, fn ->
        Code.eval_quoted(
          quote do
            import NbTs.Sigil
            ~TS"const x: number = 'string'"
          end
        )
      end
    end

    test "rejects invalid generic syntax" do
      assert_raise CompileError, ~r/Invalid TypeScript syntax/, fn ->
        Code.eval_quoted(
          quote do
            import NbTs.Sigil
            ~TS"Array<"
          end
        )
      end
    end
  end

  describe "~TS sigil - edge cases" do
    test "validates empty object type" do
      assert {:typescript_validated, "{}"} = ~TS"{}"
    end

    test "validates complex nested unions" do
      assert {:typescript_validated,
              "{ type: 'user'; data: { id: number } } | { type: 'post'; data: { title: string } }"} =
               ~TS"{ type: 'user'; data: { id: number } } | { type: 'post'; data: { title: string } }"
    end

    test "validates type with nested generics" do
      assert {:typescript_validated, "Record<string, Array<number>>"} =
               ~TS"Record<string, Array<number>>"
    end

    test "validates conditional types with concrete types" do
      assert {:typescript_validated, "string extends string ? string : number"} =
               ~TS"string extends string ? string : number"
    end

    test "validates mapped types with literal keys" do
      assert {:typescript_validated, "{ [K in 'a' | 'b']: string }"} =
               ~TS"{ [K in 'a' | 'b']: string }"
    end
  end

  describe "~TS sigil - usage in serializers" do
    test "can be used in field metadata" do
      # Simulate what happens in a serializer
      metadata = %{
        name: :settings,
        type: :typescript,
        opts: [type: ~TS"Record<string, unknown>"]
      }

      assert {:typescript_validated, "Record<string, unknown>"} = metadata.opts[:type]
    end

    test "can be used for complex field types" do
      metadata = %{
        name: :filters,
        type: :typescript,
        opts: [type: ~TS"{ search?: string; status?: 'active' | 'inactive' }"]
      }

      assert {:typescript_validated, "{ search?: string; status?: 'active' | 'inactive' }"} =
               metadata.opts[:type]
    end
  end
end
