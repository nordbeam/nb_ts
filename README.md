# NbTs

TypeScript type generation and validation for Elixir applications.

## Features

- **~TS Sigil**: Compile-time TypeScript type validation with full type checking
- **Type Generation**: Generate TypeScript interfaces from NbSerializer serializers
- **Inertia Integration**: Generate type-safe page props for Inertia.js applications
- **Fast Validation**: Uses tsgo (10x faster than tsc) for full type checking
- **Zero Config**: Native binaries - no npm/Node.js or Rust toolchain required

## Installation

### Quick Start (Recommended for Inertia Projects)

If you're using [NbInertia](https://github.com/nordbeam/nb_inertia), NbTs is automatically installed and configured:

```bash
mix nb_inertia.install --typescript
```

This handles complete setup:
- Adds `nb_ts` dependency
- Creates TypeScript output directory (`assets/js/types`)
- Adds `mix ts.gen` alias for manual type generation
- Creates example TypeScript files

### Manual Installation

Add `nb_ts` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:nb_ts, "~> 0.1"}
  ]
end
```

Then run:

```bash
mix deps.get
```

#### Mix Alias

Add a convenient alias for manual type generation:

```elixir
# mix.exs
defp aliases do
  [
    "ts.gen": ["nb_ts.gen.types"]
  ]
end
```

Create the output directory:

```bash
mkdir -p assets/js/types
```

#### Automatic Type Generation (Recommended)

Configure automatic type generation that runs during compilation:

```elixir
# mix.exs
def project do
  [
    compilers: [:nb_ts] ++ Mix.compilers(),
    nb_ts: [
      output_dir: "assets/js/types",
      auto_generate: true
    ]
  ]
end
```

With this configuration, types are automatically regenerated when you compile your project. The generator uses incremental compilation - only changed modules are processed, making it 10-50x faster for typical changes.

#### Manual Type Generation

You can also generate types manually after making changes:

```bash
mix ts.gen
```

## Usage

### The ~TS Sigil

Import the sigil to validate TypeScript types at compile time:

```elixir
import NbTs.Sigil
```

#### In NbSerializer Serializers

```elixir
defmodule MyApp.UserSerializer do
  use NbSerializer.Serializer

  field :id, :number
  field :name, :string
  field :metadata, :typescript, type: ~TS"{ [key: string]: any }"
  field :status, :typescript, type: ~TS"'active' | 'inactive' | 'pending'"
  field :settings, :typescript, type: ~TS"Record<string, unknown>"
end
```

#### In Inertia Pages

```elixir
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  use NbInertia.Controller
  import NbTs.Sigil

  inertia_page :index do
    prop :users, type: ~TS"Array<User>"
    prop :filters, type: ~TS"{ search?: string; status?: string }"
    prop :pagination, type: ~TS"{ page: number; total: number }"
  end

  def index(conn, params) do
    # Your controller logic
    render_inertia(conn, :index, users: users, filters: filters, pagination: pagination)
  end
end
```

#### Compile-Time Validation

Invalid TypeScript syntax causes compilation errors:

```elixir
# This will fail to compile:
field :bad, :typescript, type: ~TS"{ invalid syntax"

# Error message:
# ** (CompileError) Invalid TypeScript syntax in ~TS sigil
# Error: Expected '}' but found end of file
```

### Generating TypeScript Interfaces

#### Automatic Generation (Recommended)

The recommended approach is to enable automatic type generation via the Mix compiler. Add this configuration to your `mix.exs`:

```elixir
def project do
  [
    compilers: [:nb_ts] ++ Mix.compilers(),
    nb_ts: [
      output_dir: "assets/js/types",
      auto_generate: true
    ]
  ]
end
```

Types will automatically regenerate during compilation (`mix compile`). The compiler uses incremental generation - only changed modules are reprocessed, providing 10-50x faster updates for typical changes.

#### Manual Generation

You can also generate types manually using the Mix task:

```bash
mix nb_ts.gen.types
```

Or, if you configured the alias:

```bash
mix ts.gen
```

#### Options

- `--output-dir DIR` - Output directory (default: `assets/js/types`)
- `--validate` - Validate generated TypeScript using tsgo
- `--verbose` - Show detailed output

#### Examples

```bash
# Basic generation
mix nb_ts.gen.types

# Custom output directory with validation
mix nb_ts.gen.types --output-dir assets/types --validate

# Verbose mode
mix nb_ts.gen.types --verbose
```

#### What Gets Generated

NbTs generates TypeScript files for:

1. **NbSerializer Serializers** - All serializers in your application
2. **Inertia Page Props** - Props defined with `inertia_page`
3. **Shared Props** - Props defined with `inertia_shared` or `NbInertia.SharedProps`
4. **Index File** - Central `index.ts` that exports all types

### Using Generated Types in TypeScript

Import and use the generated types in your React/TypeScript components:

```typescript
import type { User, UsersIndexProps } from './types';

export default function UsersIndex({ users, filters, pagination }: UsersIndexProps) {
  // TypeScript knows the exact shape of your props!
  return (
    <div>
      <h1>Users ({pagination.total})</h1>
      {users.map((user: User) => (
        <div key={user.id}>
          {user.name} - {user.status}
        </div>
      ))}
    </div>
  );
}
```

## Generated Files Structure

After running type generation, you'll have:

```
assets/js/types/
├── index.ts              # Central export file
├── User.ts               # From UserSerializer
├── Post.ts               # From PostSerializer
├── UsersIndexProps.ts    # From inertia_page :users_index
└── AuthSharedProps.ts    # From SharedProps modules
```

## Type Generation Workflow

### Automatic Generation (Recommended)

With the Mix compiler configured (see Installation section), types are automatically regenerated whenever you compile your project:

```bash
mix compile
# Types are automatically generated for changed modules
```

The compiler tracks module changes using a manifest file and only regenerates types for modified modules, making it 10-50x faster than full regeneration.

### Manual Generation

If you prefer manual control, you can generate types on demand:

```bash
mix ts.gen
```

This command generates types when:
- Serializers are modified
- Inertia page definitions change
- SharedProps modules are updated

## How It Works

NbTs provides two key features:

### 1. TypeScript Validation

NbTs uses [tsgo](https://github.com/microsoft/typescript-go) (Microsoft's native Go TypeScript compiler) for full type checking in the `~TS` sigil.

**Why tsgo?**
- **Full Type Checking**: Validates types, not just syntax
- **10x Faster**: ~10-20ms validation vs 50-200ms for traditional tsc
- **Native Binary**: No npm or Node.js runtime dependency
- **Drop-in Replacement**: Uses same CLI API as TypeScript compiler

**Installation:**

Download tsgo binaries (required for full type checking):

```bash
mix nb_ts.download_tsgo
```

This downloads tsgo binaries for all platforms (~36 MB total). Only the binary for your platform will be used at runtime (~6 MB).

**Configuration:**

```elixir
# config/config.exs
config :nb_ts,
  # Pool size for concurrent validations (default: max(schedulers, 10))
  tsgo_pool_size: 10,

  # Validation timeout in milliseconds (default: 30_000)
  tsgo_timeout: 30_000
```

**Performance:**
- Validation time: 10-20ms per type check
- Throughput: 500-1000 validations/second with default pool size
- Memory: ~60-100 MB for pool of 10 workers

### 2. Type Generation

**Automatic (via Mix Compiler):**
- Custom Mix compiler integrated into your build pipeline
- Incremental generation using manifest-based change tracking
- Only regenerates types for modified modules
- 10-50x faster than full regeneration for typical changes

**Manual (via Mix Task):**
- On-demand generation with `mix nb_ts.gen.types`
- Full regeneration of all types
- Useful for one-time generation or manual workflows

## Related Projects

- **[NbSerializer](https://github.com/nordbeam/nb_serializer)** - High-performance JSON serialization for Elixir
- **[NbInertia](https://github.com/nordbeam/nb_inertia)** - Advanced Inertia.js integration for Phoenix
- **[NbVite](https://github.com/nordbeam/nb_vite)** - Vite integration for Phoenix

## Documentation

Full documentation is available on [HexDocs](https://hexdocs.pm/nb_ts).

## License

MIT License. See [LICENSE](LICENSE) for details.

## Credits

Built by [Nordbeam](https://github.com/nordbeam). Extracted from [NbSerializer](https://github.com/nordbeam/nb_serializer) to provide standalone TypeScript tooling for Elixir applications.
