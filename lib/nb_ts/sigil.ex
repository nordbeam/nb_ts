defmodule NbTs.Sigil do
  @moduledoc """
  TypeScript type validation with the ~TS sigil.

  Provides compile-time validation of TypeScript type syntax using tsgo for full type checking.

  ## Usage

      import NbTs.Sigil

      # In SharedProps
      inertia_shared do
        prop :flash, type: ~TS"{ info?: string; error?: string }", nullable: true
        prop :config, type: ~TS"Record<string, unknown>"
        prop :metadata, type: ~TS"{ [key: string]: any }"
      end

      # In Inertia pages
      inertia_page :dashboard do
        prop :stats, type: ~TS"{ total: number; active: number }"
        prop :user, type: ~TS"{ id: number; name: string; email: string }"
      end

  ## Validation

  The sigil validates TypeScript syntax at compile time. Invalid syntax will cause
  a compilation error with a helpful message:

      # This will fail to compile:
      prop :bad, type: ~TS"{ invalid syntax"

      ** (CompileError) Invalid TypeScript syntax:

      TypeScript syntax error: Expected '}' but found end of file

      Code: "{ invalid syntax"

  ## Supported Types

  All TypeScript type syntax is supported:

  - Object types: `~TS"{ foo: string; bar: number }"`
  - Arrays: `~TS"string[]"` or `~TS"Array<string>"`
  - Unions: `~TS"'active' | 'inactive' | 'pending'"`
  - Generics: `~TS"Record<string, unknown>"`
  - Tuples: `~TS"[string, number]"`
  - Utility types: `~TS"Partial<User>"`, `~TS"Pick<User, 'id' | 'name'>"`
  - Nested types: `~TS"{ user: { id: number }; posts: Array<Post> }"`

  ## Implementation

  Uses tsgo (Microsoft's TypeScript compiler in Go) for full TypeScript type checking:
  - **Full type checking** - Validates types, not just syntax
  - **10x faster than tsc** - ~10-20ms validation vs 50-200ms
  - **Native binary** - No npm or Node.js required

  Binaries are automatically downloaded from GitHub releases.
  """

  @doc """
  TypeScript sigil with compile-time validation.

  Validates TypeScript type syntax and returns the type string unchanged.
  Compilation fails if the TypeScript syntax is invalid.

  ## Examples

      ~TS"string"
      ~TS"{ id: number; name: string }"
      ~TS"Array<{ id: number }>"
      ~TS"'success' | 'error' | 'pending'"
  """
  defmacro sigil_TS({:<<>>, meta, [string]}, _opts) when is_binary(string) do
    # Validate at compile time using tsgo
    case NbTs.Generator.validate(string) do
      {:ok, _validated} ->
        # Return a tagged tuple so the DSL can detect validated TypeScript types
        quote do
          {:typescript_validated, unquote({:<<>>, meta, [string]})}
        end

      {:error, reason} ->
        # Raise compile error with helpful context
        raise CompileError,
          file: __CALLER__.file,
          line: __CALLER__.line,
          description: """
          Invalid TypeScript syntax in ~TS sigil

          Error: #{reason}

          Invalid code:
              ~TS"#{string}"

          Location: #{__CALLER__.file}:#{__CALLER__.line}

          Common TypeScript type patterns:

          Object types:
              ~TS"{ id: number; name: string }"
              ~TS"{ key: string; value: any }"

          Arrays:
              ~TS"string[]"
              ~TS"Array<number>"
              ~TS"Array<{ id: number }>"

          Unions and literals:
              ~TS"'active' | 'inactive' | 'pending'"
              ~TS"string | number | null"

          Utility types:
              ~TS"Record<string, unknown>"
              ~TS"Partial<{ name: string }>"
              ~TS"Pick<User, 'id' | 'name'>"

          Index signatures:
              ~TS"{ [key: string]: any }"
              ~TS"Record<string, number>"

          Troubleshooting:
          - Check for matching brackets: { }, [ ], < >
          - Ensure property names are valid
          - Use single or double quotes for string literals
          - Separate union types with |
          - Escape special characters if needed

          See: https://hexdocs.pm/nb_ts/NbTs.Sigil.html
          """
    end
  end
end
