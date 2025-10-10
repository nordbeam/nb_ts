# NbTs Usage Rules

## What is NbTs?

TypeScript type generation and validation for Elixir:
- `~TS` sigil for compile-time TypeScript validation
- Auto-generate TypeScript interfaces from NbSerializer serializers
- Type-safe Inertia.js page props with oxc parser (Rust)

## Installation

```bash
# Automatic (recommended)
mix nb_ts.install

# Manual: Add to mix.exs
{:nb_ts, "~> 0.1"}
```

## Core Usage

### 1. ~TS Sigil (Compile-Time Validation)

```elixir
import NbTs.Sigil

# In serializers
field :metadata, :typescript, type: ~TS"{ [key: string]: any }"
field :status, :typescript, type: ~TS"'active' | 'inactive' | 'pending'"

# In Inertia pages
prop :stats, type: ~TS"{ total: number; active: number }"
prop :users, type: ~TS"User", array: true
```

**Supported syntax:** Objects, arrays, unions, generics, index signatures, utility types

### 2. Generate TypeScript

```bash
mix nb_ts.gen.types                          # Basic
mix nb_ts.gen.types --validate              # With validation
mix nb_ts.gen.types --output-dir assets/types --verbose
```

Generates interfaces for serializers, Inertia pages, SharedProps, and `index.ts`

### 3. Use in TypeScript/React

```typescript
import type { User, UsersIndexProps } from './types';

export default function UsersIndex({ users }: UsersIndexProps) {
  return users.map((user: User) => <div>{user.name}</div>);
}
```

## Configuration

**Mix task options:**
- `--output-dir DIR` - Output directory (default: `assets/js/types`)
- `--validate` - Validate generated files
- `--verbose` - Detailed output

**Install options:**
- `--output-dir DIR`, `--watch`, `--yes`

## Common Patterns

```elixir
# Optional/nullable
prop :email, type: ~TS"string", optional: true
prop :avatar, type: ~TS"string", nullable: true

# Arrays
prop :tags, type: ~TS"string", array: true

# Complex types
prop :config, type: ~TS"Record<string, unknown>"
prop :status, type: ~TS"'pending' | 'approved' | 'rejected'"
```

## Best Practices

1. Always use `~TS` for custom TypeScript types
2. Run `mix ts.gen` after modifying serializers/page props
3. Enable `--validate` to catch issues early
4. Commit generated types to version control

## Troubleshooting

**Invalid TypeScript:** Check brackets, colons, semicolons, union syntax (`|` not `,`)
**NIF not loaded:** Auto-falls back to Elixir validation
**Types not generating:** Compile modules first
