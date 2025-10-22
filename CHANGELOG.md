# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **BREAKING**: Migrated from oxc NIF to tsgo (Microsoft's Go-based TypeScript compiler)
- TypeScript validation now uses real TypeScript type checking instead of syntax-only validation
- Improved validation performance: ~70ms sequential, ~16ms with pool concurrency
- Validation now uses NimblePool for resource management and concurrency control
- TsgoPool only starts in dev/test environments (validation is compile-time only, no runtime overhead in production)

### Removed
- Removed oxc parser and Rust native code (entire `native/` directory)
- Removed rustler and rustler_precompiled dependencies
- Removed `NbTs.Validator` module (oxc NIF wrapper)
- Removed Elixir fallback validation (no longer needed)

### Added
- Added `NbTs.TsgoPool` for managing tsgo binary processes via NimblePool
- Added `NbTs.TsgoValidator` for direct tsgo validation
- Added automatic tsgo binary download via `mix nb_ts.download_tsgo`
- Added comprehensive benchmarking suite (`bench/validation_bench.exs`)
- Added 65+ tests for TsgoPool covering concurrency, edge cases, and real-world scenarios
- Added 30+ tests for ~TS sigil validation

### Fixed
- TypeScript validation now catches actual type errors, not just syntax errors
- Better error messages from TypeScript compiler diagnostics

## [0.1.0] - 2025-01-10

### Added
- Initial release
- ~TS sigil for compile-time TypeScript type validation
- TypeScript interface generation from NbSerializer serializers
- Inertia page props type generation
- oxc parser integration via Rustler NIF
- Mix task `nb_ts.gen.types` for generating TypeScript files
- Support for circular dependency detection in type generation
- Optional Elixir fallback validation when NIF not available

### Extracted
- Extracted from NbSerializer v0.1.0
- Module mappings:
  - `NbSerializer.TypeScript` → `NbTs.Sigil`
  - `NbSerializer.TypeScript.Validator` → `NbTs.Validator`
  - `NbSerializer.Typelizer.Interface` → `NbTs.Interface`
  - `NbSerializer.Typelizer.Validator` → `NbTs.Generator`
  - `NbSerializer.Typelizer.TypeMapper` → `NbTs.TypeMapper`
  - `NbSerializer.Typelizer.Registry` → `NbTs.Registry`
  - `Mix.Tasks.NbSerializer.Gen.Types` → `Mix.Tasks.NbTs.Gen.Types`
