# NbTs

TypeScript type generation and validation for Elixir.

## Features

- **~TS Sigil**: Compile-time TypeScript type validation
- **Type Generation**: Generate TypeScript interfaces from NbSerializer serializers
- **Inertia Integration**: Generate page props types for Inertia.js applications
- **Fast Validation**: Uses oxc parser (Oxidation Compiler) via Rustler NIF

## Installation

### Automatic Installation (Recommended)

The easiest way to install NbTs is using the installer task with Igniter:

```bash
mix nb_ts.install
```

This will:
- Add `nb_ts` to your dependencies
- Create the TypeScript output directory
- Create or update `tsconfig.json`
- Add a `mix ts.gen` alias for type generation
- Create an example file showing ~TS sigil usage
- Run initial type generation

Options:
- `--output-dir` - Where to generate types (default: `assets/js/types`)
- `--watch-mode` - Set up file watcher for auto-generation
- `--yes` - Skip confirmations

Examples:
```bash
# Basic installation
mix nb_ts.install

# Install with custom output directory
mix nb_ts.install --output-dir assets/types

# Install with file watcher for auto-generation
mix nb_ts.install --watch-mode
```

### Manual Installation

Add `nb_ts` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nb_ts, "~> 0.1"}
  ]
end
```

Then create the output directory and add a mix alias:

```bash
mkdir -p assets/js/types
```

```elixir
# In mix.exs
defp aliases do
  [
    "ts.gen": ["nb_ts.gen.types"]
  ]
end
```

## Usage

### The ~TS Sigil

Import the sigil and use it to validate TypeScript types at compile time:

```elixir
import NbTs.Sigil

# In NbSerializer serializers
defmodule MyApp.UserSerializer do
  use NbSerializer.Serializer

  field :id, :number
  field :metadata, :typescript, type: ~TS"{ [key: string]: any }"
  field :status, :typescript, type: ~TS"'active' | 'inactive' | 'pending'"
end

# In Inertia pages
defmodule MyAppWeb.UserController do
  use NbSerializer.Inertia.Controller

  inertia_page :index do
    prop :users, type: ~TS"Array<User>", array: true
    prop :filters, type: ~TS"{ search?: string; status?: string }"
  end
end
```

Invalid TypeScript syntax will cause a compilation error:

```elixir
# This will fail to compile:
field :bad, :typescript, type: ~TS"{ invalid syntax"
```

### Generating TypeScript Interfaces

Generate TypeScript interfaces from your serializers and Inertia pages:

```bash
mix nb_ts.gen.types
```

Options:
- `--output-dir` - Output directory (default: `assets/js/types`)
- `--validate` - Validate generated TypeScript files
- `--verbose` - Show detailed output

Example:
```bash
mix nb_ts.gen.types --output-dir assets/types --validate
```

This will generate TypeScript interface files for:
- All NbSerializer serializers in your application
- All Inertia page props
- All SharedProps modules

### Using Generated Types in TypeScript

Import the generated types in your TypeScript/React code:

```typescript
import type { User, UsersIndexProps } from './types';

export default function UsersIndex({ users, filters }: UsersIndexProps) {
  // TypeScript knows the shape of your props!
  return (
    <div>
      {users.map((user: User) => (
        <div key={user.id}>{user.name}</div>
      ))}
    </div>
  );
}
```

## How It Works

NbTs uses the [oxc parser](https://oxc-project.github.io/) (Oxidation Compiler) via Rustler NIF for fast, accurate TypeScript validation. Precompiled binaries are automatically downloaded - no Rust toolchain required.

## License

MIT

## Credits

Extracted from [NbSerializer](https://github.com/nordbeam/nb_serializer) to provide standalone TypeScript tooling for Elixir applications.
