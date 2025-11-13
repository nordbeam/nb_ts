defmodule NbTs do
  @moduledoc """
  NbTs - TypeScript type generation for Elixir.

  NbTs provides tools for working with TypeScript in your Elixir applications:

  1. **~TS Sigil** - Convenient TypeScript type annotation
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

  ## Configuration

  Configure NbTs in your `config/config.exs`:

  ```elixir
  config :nb_ts,
    output_dir: "assets/js/types",    # Where to generate TypeScript files
    auto_generate: true,              # Auto-generate on compile (dev only)
    watch: true,                      # Watch for file changes (dev only)
    validate: false                   # Validate TypeScript (not yet implemented)
  ```

  ## The ~TS Sigil

  The ~TS sigil provides a convenient way to specify TypeScript types:

      import NbTs.Sigil

      # Specify TypeScript types
      type = ~TS"string"
      type = ~TS"{ id: number; name: string }"
      type = ~TS"Array<User>"
      type = ~TS"'active' | 'inactive'"

  Note: The ~TS sigil does NOT perform compile-time validation. It simply
  tags the type string for use by the type generator. Validation support
  may be added in a future release.

  ## Generating TypeScript Interfaces

  Generate TypeScript interfaces from your NbSerializer serializers:

      mix nb_ts.gen.types

  Options:
  - `--output-dir` - Output directory (default: `assets/js/types`)
  - `--verbose` - Show detailed output

  ## Module Overview

  - `NbTs.Config` - Centralized configuration
  - `NbTs.Sigil` - The ~TS sigil for type annotation
  - `NbTs.Interface` - Generate TypeScript interfaces from metadata
  - `NbTs.Generator` - Orchestrate TypeScript type generation
  - `NbTs.TypeMapper` - Map Elixir types to TypeScript types
  - `NbTs.Registry` - Track registered serializers
  - `NbTs.Field` - Represent TypeScript fields
  - `NbTs.GeneratorOptions` - Configuration for generation

  ## Automatic Type Generation

  Types are automatically regenerated during development when:
  - A serializer module is recompiled
  - A controller module with Inertia pages is recompiled

  This requires `auto_generate: true` in your config (default in dev).
  """

  @doc """
  Returns the version of NbTs.
  """
  def version do
    Application.spec(:nb_ts, :vsn) |> to_string()
  end
end
