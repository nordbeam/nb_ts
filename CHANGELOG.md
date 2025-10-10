# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
