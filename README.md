# Swift Wasmtime

Swift Wasmtime is a SwiftPM wrapper around the official Wasmtime C API. The
package vendors Wasmtime C API static libraries for macOS and Linux, exposes a
small Swift 6 API, and keeps the C ownership rules explicit.

## Current Scope

- Core runtime wrappers: `Config`, `Engine`, `Store`, `Module`, `Instance`,
  `Linker`, `Func`, `Value`, `Trap`, `WasmtimeError`, and `WasiConfig`.
- Early component-model wrappers: `Component`, `ComponentLinker`,
  `ComponentInstance`, and `ComponentFunction` for compiling components,
  registering WASIp2/WASI HTTP host interfaces, instantiating components, and
  calling zero-parameter, zero-result component functions.
- Module compilation from Wasm bytes, `Data`, or WAT text via Wasmtime's
  `wat2wasm` C API.
- Direct instantiation, linker instantiation, exported function lookup, scalar
  calls for `i32`, `i64`, `f32`, and `f64`, trap/error conversion, and basic
  WASI configuration including arguments, environment, stdio, and preopened
  directories.
- Vendored Wasmtime version: `v44.0.1`.

## Version Tags

Git release tags use SwiftPM-friendly semantic versions without a leading `v`.
For example, this package tag is `44.0.1`, matching the vendored Wasmtime
`v44.0.1` release. Upstream Wasmtime still uses `v`-prefixed tags, so scripts
and vendored paths keep the upstream spelling where they interact with
Bytecode Alliance release assets.

## Build And Test

On this machine the Xcode toolchain is the known-good path:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
swift test --disable-sandbox
```

Coverage:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
scripts/test-coverage.sh
```

The coverage script focuses on `Sources/Wasmtime` and excludes the vendored C
headers, C shim, fixtures, and package plumbing. Lines marked
`coverage:ignore` are narrow defensive C-interop branches that cannot be
reached deterministically from Swift without faking Wasmtime allocation failure
or intentionally triggering a process abort.

## Vendoring Wasmtime

To refresh the vendored C API artifacts:

```sh
scripts/vendor-wasmtime.sh v44.0.1
```

The script downloads release metadata from GitHub, reads the official asset
digests, downloads the four supported `*-c-api.tar.xz` archives, verifies
SHA256 checksums, copies headers, and stores static libraries under
`Vendor/Wasmtime`.
