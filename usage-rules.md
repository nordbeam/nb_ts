# NbTs Usage Rules

## Overview

NbTs provides TypeScript type generation and validation for Elixir applications:
- **`~TS` sigil** - Compile-time TypeScript validation using oxc parser
- **Type generation** - Auto-generate TypeScript interfaces from NbSerializer serializers
- **Inertia integration** - Type-safe page props for Inertia.js applications
- **Zero config** - Precompiled binaries, no Rust toolchain required

## Installation

### Quick Start (with NbInertia)
```bash
mix nb_inertia.install --typescript
```

### Manual Installation
```elixir
# mix.exs
def deps do
  [
    {:nb_ts, "~> 0.1"}
  ]
end
```

## Core Usage

### 1. ~TS Sigil (Compile-Time Validation)

Import the sigil for compile-time TypeScript validation:

```elixir
import NbTs.Sigil
```

#### In NbSerializer Serializers
```elixir
defmodule MyApp.UserSerializer do
  use NbSerializer.Serializer
  import NbTs.Sigil

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
  use NbInertia.Controller
  import NbTs.Sigil

  inertia_page :index do
    prop :stats, type: ~TS"{ total: number; active: number }"
    prop :users, type: ~TS"Array<User>"
    prop :filters, type: ~TS"{ search?: string }"
  end
end
```

#### Supported TypeScript Syntax
- Objects: `~TS"{ foo: string; bar: number }"`
- Arrays: `~TS"string[]"` or `~TS"Array<string>"`
- Unions: `~TS"'active' | 'inactive'"`
- Generics: `~TS"Record<string, unknown>"`
- Index signatures: `~TS"{ [key: string]: any }"`
- Utility types: `~TS"Partial<User>"`, `~TS"Pick<User, 'id'>"`
- Optional fields: `~TS"{ name?: string }"`
- Tuples: `~TS"[string, number]"`

### 2. Type Generation

#### Basic Usage
```bash
mix nb_ts.gen.types                  # Generate all types
mix ts.gen                           # If alias configured
```

#### With Options
```bash
mix nb_ts.gen.types --validate              # Validate with oxc
mix nb_ts.gen.types --output-dir assets/ts  # Custom output
mix nb_ts.gen.types --verbose               # Detailed output
```

#### What Gets Generated
- **Serializers** → TypeScript interfaces (e.g., `User.ts`, `Post.ts`)
- **Inertia pages** → Page props types (e.g., `UsersIndexProps.ts`)
- **SharedProps** → Shared props types (e.g., `AuthSharedProps.ts`)
- **Index file** → Central `index.ts` exporting all types

#### Command Options
- `--output-dir DIR` - Output directory (default: `assets/js/types`)
- `--validate` - Validate generated TypeScript with oxc parser
- `--verbose` - Show detailed generation output

### 3. Automatic Type Generation (Optional)

Add `NbTs.Watcher` to your supervision tree for automatic regeneration on file changes:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    # ... other children
    {NbTs.Watcher, output_dir: "assets/js/types"}
  ]
  # ...
end
```

### 4. Use in TypeScript/React

```typescript
import type { User, UsersIndexProps } from './types';

export default function UsersIndex({ users, filters }: UsersIndexProps) {
  return (
    <div>
      {users.map((user: User) => (
        <div key={user.id}>{user.name} - {user.status}</div>
      ))}
    </div>
  );
}
```

## Common Patterns

### Optional and Nullable Props
```elixir
# Optional (can be omitted)
prop :email, type: ~TS"string", optional: true
prop :description, type: ~TS"string | undefined"

# Nullable (can be null)
prop :avatar, type: ~TS"string", nullable: true
prop :avatar_url, type: ~TS"string | null"
```

### Arrays
```elixir
# Array notation
prop :tags, type: ~TS"string[]"
prop :ids, type: ~TS"number[]"

# Generic Array notation
prop :users, type: ~TS"Array<User>"
prop :posts, type: ~TS"Array<{ id: number; title: string }>"
```

### Complex Types
```elixir
# Union types
prop :status, type: ~TS"'pending' | 'approved' | 'rejected'"
prop :value, type: ~TS"string | number | null"

# Record types
prop :config, type: ~TS"Record<string, unknown>"
prop :meta, type: ~TS"Record<string, string | number>"

# Index signatures
prop :metadata, type: ~TS"{ [key: string]: any }"
prop :translations, type: ~TS"{ [locale: string]: string }"

# Utility types
prop :partial_user, type: ~TS"Partial<User>"
prop :user_subset, type: ~TS"Pick<User, 'id' | 'name'>"
```

## Best Practices

1. **Always use `~TS` for custom TypeScript types** - Ensures compile-time validation
2. **Run type generation after schema changes** - Keep TypeScript in sync with Elixir
3. **Enable `--validate` in CI** - Catch TypeScript errors before deployment
4. **Commit generated types** - Ensures frontend devs always have latest types
5. **Use `NbTs.Watcher` in development** - Automatic type regeneration on file changes
6. **Prefer utility types** - Use `Record<K, V>` over `{ [key: K]: V }` for readability

## Troubleshooting

### Invalid TypeScript Syntax
**Problem:** Compilation fails with `~TS` sigil errors

**Solution:** Check for:
- Matching brackets: `{ }`, `[ ]`, `< >`
- Correct colons and semicolons
- Union syntax uses `|` not `,`
- String literals use quotes: `'active'` not `active`

### NIF Not Loaded
**Problem:** Warning about NIF not available

**Solution:** NbTs automatically falls back to Elixir validation. Precompiled binaries are downloaded on first use. If issues persist:
```bash
mix deps.clean nb_ts --build
mix deps.get
mix deps.compile
```

### Types Not Generating
**Problem:** `mix nb_ts.gen.types` doesn't generate expected files

**Solution:**
1. Ensure modules are compiled: `mix compile --force`
2. Check serializers use `NbSerializer.Serializer`
3. Check pages use `NbInertia.Controller` with `inertia_page`
4. Use `--verbose` flag to see what's being processed

### Watcher Not Working
**Problem:** Types don't regenerate automatically

**Solution:** Verify `NbTs.Watcher` is in supervision tree and receiving file system events:
```elixir
# lib/my_app/application.ex
children = [
  {NbTs.Watcher, output_dir: "assets/js/types"}
]
```
