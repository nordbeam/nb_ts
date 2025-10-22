# Migration to tsgo

This guide covers migrating from oxc to tsgo for TypeScript validation.

## Breaking Changes

None - tsgo is a drop-in replacement with better validation.

## Benefits

- **Full type checking** (not just syntax)
- **10x faster than tsc** (~10-20ms vs 50-200ms)
- **Catches type errors that syntax-only validators miss**

## Setup

1. Download tsgo binaries:
   ```bash
   mix nb_ts.download_tsgo
   ```

2. Update config (optional):
   ```elixir
   config :nb_ts, tsgo_pool_size: 20
   ```

3. Run tests:
   ```bash
   mix test
   ```

## Implementation

NbTs uses tsgo exclusively for full TypeScript type checking. The validator provides comprehensive type validation at compile time with no fallback mechanisms.
