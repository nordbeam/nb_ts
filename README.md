# NbTs

TypeScript type generation and validation for Elixir applications.

## Features

- **~TS Sigil**: Compile-time TypeScript type annotations
- **Type Generation**: Generate TypeScript interfaces from NbSerializer serializers
- **Inertia Integration**: Generate type-safe page props for Inertia.js applications
- **Modal Types**: Automatic generation of modal/slideover configuration types
- **Form Inputs**: Generate `FormInputs` interfaces for Inertia forms
- **Incremental Generation**: Only regenerates types for changed modules (10-50x faster)
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
    {:nb_ts, github: "nordbeam/nb_ts"}
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

#### The ~TS Sigil

The `~TS` sigil marks TypeScript type strings for code generation. The type string is passed through to the generated TypeScript files as-is.

```elixir
# These type strings are emitted directly to TypeScript
field :metadata, :typescript, type: ~TS"Record<string, any>"
field :status, :typescript, type: ~TS"'active' | 'inactive'"
```

**Note:** The sigil does not perform compile-time TypeScript validation. Use your IDE's TypeScript language server or `tsc` to validate the generated files.

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
4. **Form Inputs** - Input interfaces for Inertia forms
5. **Modal Types** - Configuration types for modals and slideovers
6. **Index File** - Central `index.ts` that exports all types

### Modal Type Generation

When using nb_inertia's modal system, NbTs automatically generates modal configuration types:

```typescript
// Generated in types/modals.d.ts
export type ModalSize = 'sm' | 'md' | 'lg' | 'xl' | 'full';
export type ModalPosition = 'center' | 'top' | 'bottom' | 'left' | 'right';

export interface ModalConfig {
  size?: ModalSize;
  position?: ModalPosition;
  slideover?: boolean;
  closeButton?: boolean;
  closeExplicitly?: boolean;
  maxWidth?: string;
  paddingClasses?: string;
  panelClasses?: string;
  backdropClasses?: string;
}
```

Use these types for type-safe modal configuration:

```typescript
import type { ModalConfig } from '@/types';

const modalConfig: ModalConfig = {
  size: 'lg',
  position: 'center',
  closeButton: true
};
```

### Form Inputs Generation

When Inertia pages define forms, NbTs generates corresponding `FormInputs` interfaces:

```elixir
# In your controller
inertia_page :users_edit do
  prop :user, UserSerializer

  form :user_form do
    field :name, :string
    field :email, :string
    field :role, enum: ["admin", "user", "guest"]
    field :tags, list: :string
  end
end
```

Generates:

```typescript
// Generated in types/UsersEditProps.ts
export interface UsersEditProps {
  user: User;
}

export interface UsersEditFormInputs {
  name: string;
  email: string;
  role: 'admin' | 'user' | 'guest';
  tags: string[];
}
```

Use with Inertia's useForm:

```typescript
import type { UsersEditProps, UsersEditFormInputs } from '@/types';
import { useForm } from '@nordbeam/nb-inertia/react/useForm';

function EditUser({ user }: UsersEditProps) {
  const form = useForm<UsersEditFormInputs>(
    { name: user.name, email: user.email, role: user.role, tags: user.tags },
    users.update.patch(user.id)
  );
  // form.data is typed as UsersEditFormInputs
}
```

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

### 1. TypeScript Type Annotations

The `~TS` sigil provides a way to embed TypeScript type strings in your Elixir code. These are passed through to the generated TypeScript files without modification.

```elixir
# The type string "Record<string, any>" is emitted as-is to TypeScript
field :metadata, type: ~TS"Record<string, any>"
```

**Type Validation:**

For validating generated TypeScript files, we recommend using:
- Your IDE's TypeScript language server (VS Code, WebStorm, etc.)
- Running `tsc --noEmit` in your assets directory
- The `--validate` flag with `mix nb_ts.gen.types` (requires tsgo binaries)

**Optional: tsgo Integration**

For faster validation, you can optionally install [tsgo](https://github.com/nicolo-ribaudo/esbuild-tsc) binaries:

```bash
mix nb_ts.download_tsgo
```

Then use with the `--validate` flag:

```bash
mix nb_ts.gen.types --validate
```

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
