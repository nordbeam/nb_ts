defmodule NbTs do
  @moduledoc """
  NbTs - TypeScript type generation and validation for Elixir.

  NbTs provides tools for working with TypeScript in your Elixir applications:

  1. **~TS Sigil** - Compile-time TypeScript type validation
  2. **Type Generation** - Generate TypeScript interfaces from NbSerializer serializers
  3. **Inertia Integration** - Generate page props types for Inertia.js applications

  ## Installation

  Add `nb_ts` to your `mix.exs` dependencies:

  ```elixir
  def deps do
    [
      {:nb_ts, "~> 0.1"}
    ]
  end
  ```

  ## The ~TS Sigil

  The ~TS sigil provides compile-time validation of TypeScript type syntax:

      import NbTs.Sigil

      # Valid TypeScript types
      type = ~TS"string"
      type = ~TS"{ id: number; name: string }"
      type = ~TS"Array<User>"
      type = ~TS"'active' | 'inactive'"

      # This will fail at compile time:
      type = ~TS"{ invalid syntax"

  ## Generating TypeScript Interfaces

  Generate TypeScript interfaces from your NbSerializer serializers:

      mix nb_ts.gen.types

  Options:
  - `--output-dir` - Output directory (default: `assets/js/types`)
  - `--validate` - Validate generated TypeScript
  - `--verbose` - Show detailed output

  ## Module Overview

  - `NbTs.Sigil` - The ~TS sigil for compile-time validation
  - `NbTs.Validator` - NIF module for TypeScript validation (Rust)
  - `NbTs.Interface` - Generate TypeScript interfaces from metadata
  - `NbTs.Generator` - Validate generated TypeScript code
  - `NbTs.TypeMapper` - Map Elixir types to TypeScript types
  - `NbTs.Registry` - Track registered serializers

  ## Implementation

  Uses the oxc parser (Oxidation Compiler) via Rustler NIF with precompiled
  binaries. No Rust toolchain required - binaries are automatically downloaded
  from GitHub releases.
  """

  @doc """
  Returns the version of NbTs.
  """
  def version do
    Application.spec(:nb_ts, :vsn) |> to_string()
  end
end
