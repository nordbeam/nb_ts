defmodule NbTs.Sigil do
  @moduledoc """
  TypeScript type sigil with the ~TS sigil.

  Provides a convenient way to specify TypeScript types in Elixir code.

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

  ## Supported Types

  Any valid TypeScript type syntax can be used:

  - Object types: `~TS"{ foo: string; bar: number }"`
  - Arrays: `~TS"string[]"` or `~TS"Array<string>"`
  - Unions: `~TS"'active' | 'inactive' | 'pending'"`
  - Generics: `~TS"Record<string, unknown>"`
  - Tuples: `~TS"[string, number]"`
  - Utility types: `~TS"Partial<User>"`, `~TS"Pick<User, 'id' | 'name'>"`
  - Nested types: `~TS"{ user: { id: number }; posts: Array<Post> }"`

  Note: No compile-time validation is performed. The type string is passed through as-is.
  """

  @doc """
  TypeScript sigil that returns the type string unchanged.

  No compile-time validation is performed. The type string is passed through as-is.

  ## Examples

      ~TS"string"
      ~TS"{ id: number; name: string }"
      ~TS"Array<{ id: number }>"
      ~TS"'success' | 'error' | 'pending'"
  """
  defmacro sigil_TS({:<<>>, meta, [string]}, _opts) when is_binary(string) do
    # Return a tagged tuple so the DSL can detect TypeScript types
    # No validation is performed - the type string is returned as-is
    quote do
      {:typescript_validated, unquote({:<<>>, meta, [string]})}
    end
  end
end
