# Agent Notes

This repo intentionally wraps Wasmtime through the C API, not through Rust
source builds. Keep the Swift layer small, memory-safe at the API boundary, and
well tested.

## Working Rules

- Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` when building
  locally on this machine.
- Set `CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache` so Swift/Clang
  module caches stay inside the workspace.
- Use `swift test --disable-sandbox` if SwiftPM's own sandbox integration fails
  under the outer Codex sandbox.
- Do not make `Store`, `Instance`, `Linker`, or `Func` broadly `Sendable`
  without adding serialization, because Wasmtime's C API allows movement across
  threads but forbids concurrent mutable access through aliasing contexts.
- Keep `Engine`, `Module`, scalar values, traps, and errors `Sendable` where
  that remains sound.

## Verification Expectations

- Run `swift build` after C interop changes.
- Run `swift test` after API changes.
- Run `scripts/test-coverage.sh` before declaring coverage work complete.
- `coverage:ignore` is allowed only for defensive FFI branches that cannot be
  reached deterministically from Swift, such as C allocation returning nil,
  impossible type metadata nils, Swift `String` failing UTF-8 validation, or
  intentional precondition crash branches.

## Release Tags

- Publish package release tags as plain semantic versions for SwiftPM, such as
  `44.0.1`.
- Keep upstream Wasmtime references `v`-prefixed when talking to GitHub release
  assets or vendored directories, such as `v44.0.1`.
- When updating Wasmtime, the SwiftPM tag should match the vendored Wasmtime
  version after removing the leading `v`.

## Vendored Files

`Sources/CWasmtime/include` and `Vendor/Wasmtime` are generated from
`scripts/vendor-wasmtime.sh`. Prefer regenerating them over hand-editing them.
