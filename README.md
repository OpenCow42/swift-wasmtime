# Swift Wasmtime

[![Swift Package Index](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOpenCow42%2Fswift-wasmtime%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/OpenCow42/swift-wasmtime)
[![Swift Package Index](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOpenCow42%2Fswift-wasmtime%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/OpenCow42/swift-wasmtime)

🪟 Windows is supported alongside macOS and Linux.

Swift Wasmtime is a SwiftPM wrapper around the official Wasmtime C API. The
package vendors Wasmtime C API libraries for macOS, Linux, and Windows, exposes a
small Swift 6 API, and keeps the C ownership rules explicit.

## Project Status

This is a community build/test package, not an official Wasmtime distribution.
It exists to explore a small, Swift-native API over Wasmtime while keeping usage
from SwiftPM projects as straightforward as possible.

The current vendoring model is intentionally pragmatic and somewhat subpar:
Wasmtime is implemented in Rust and distributed to C consumers as prebuilt C API
artifacts, while SwiftPM does not currently have a first-class cross-platform
story for vendored Rust-built C ABI libraries. This package therefore vendors
the official Wasmtime C API artifacts and uses linker search paths selected by
platform and architecture. Ease of use from SwiftPM is important to this project,
even though the packaging tradeoff is not as clean as a native SwiftPM C/C++
source target. Upstream Rust toolchain requirements apply when building
Wasmtime itself from source; normal Swift package consumers use the prebuilt C
API artifacts vendored here.

## Current Scope

- Core runtime wrappers: `Config`, `Engine`, `Store`, `Module`,
  `ModuleImport`, `ModuleExport`, `ModuleExternType`, `Instance`,
  `InstancePre`, `Linker`, `Extern`, `Func`, `GlobalType`, `Global`,
  `TableElementKind`, `TableElement`, `TableType`, `Table`, `MemoryType`,
  `Memory`, `Value`, `Trap`, `WasmtimeError`, and `WasiConfig`.
- Swift 6 thread-safe surface: `EngineOptions` for sendable engine
  configuration, `WasiOptions` for sendable WASI configuration, and
  `WasmtimeRuntime` for actor-serialized store execution.
- Config knobs for component model, core Wasm proposals, SIMD/relaxed SIMD,
  compilation strategy including Winch selection, Cranelift optimization,
  regalloc algorithm, flags/debug verification/NaN canonicalization, profiling
  strategy, target triples, trap handling, debug info, native unwind info,
  macOS Mach-port handling, parallel compilation, linear-memory
  reservation/guard sizing and copy-on-write initialization, fuel consumption,
  epoch interruption, and maximum Wasm stack size.
- Resource-control APIs for fuel, epoch deadlines, epoch interruption callbacks,
  store resource limits, explicit store GC, and engine epoch increments, exposed
  both through low-level `Store`/`Engine` wrappers and `WasmtimeRuntime`.
- Early component-model wrappers: `Component`, `ComponentLinker`,
  `ComponentInstance`, and `ComponentFunction` for compiling components,
  registering WASIp2/WASI HTTP host interfaces, instantiating components, and
  calling zero-parameter, zero-result component functions.
- Module compilation from Wasm bytes, `Data`, or WAT text via Wasmtime's
  `wat2wasm` C API, validation of Wasm bytes before compilation, shallow
  module cloning, compiled module serialization/deserialization artifacts, plus
  import/export type metadata inspection for functions, globals, tables, and
  memories.
- Direct instantiation, linker instantiation, exported function lookup, checked
  calls for `i32`, `i64`, `f32`, `f64`, and SIMD-backed `v128`, function
  signature introspection, trap/error conversion with typed `TrapCode`,
  host-side trap/error helpers, `WasmFrame`/`WasmTrace` diagnostics, and WASI
  configuration including arguments, environment, stdio files, stdin bytes,
  stdout/stderr callbacks, preopened directories, network inheritance, and IP
  name lookup.
- Linear memory support through `MemoryType`, `Memory`, exported memory lookup,
  safe copy-based memory reads/writes, memory growth, and actor-isolated
  `WasmtimeRuntime` memory helpers.
- Numeric scalar and `v128` global support through `GlobalType`, `Global`,
  exported global lookup, immutable and mutable global reads/writes,
  linker-defined globals, and actor-isolated `WasmtimeRuntime` global helpers.
- Table support through `TableType`, `Table`, exported table lookup, table size,
  table growth, linker-defined tables, function references, and null
  `funcref`/`externref` elements, including actor-isolated `WasmtimeRuntime`
  table helpers. Arbitrary non-null host `externref` payloads are intentionally
  deferred until broader reference value modeling exists.
- General extern lookup through `Instance.export(named:)`,
  `Instance.export(at:)`, `Instance.exports()`, `Extern`, and
  `Linker.get(store:module:name:)`. Functions, globals, tables, and memories
  have first-class wrappers today; tags and shared memories are reported by
  kind until their dedicated wrappers land.
- Linker support for WASI registration, import shadowing, host functions,
  store-bound functions, defining unknown imports as traps or default values,
  store-bound globals and memories, defining an instantiated module namespace,
  registering a module by name, cloning linker definitions, resolving a named
  module's default function, instantiating modules through that linker, and
  pre-instantiating modules with `InstancePre` for reuse across compatible
  stores. The remaining low-level extern definition surface for tags is not
  exposed yet.
- Vendored Wasmtime version: `v45.0.0`.
- Vendored platforms: macOS, Linux, and Windows on `arm64`/`x86_64`, plus
  iOS/iPadOS device and simulator slices through `Wasmtime.xcframework`.

## Runtime Safety

Prefer `WasmtimeRuntime` when values cross Swift concurrency domains. It keeps
store-bound Wasmtime handles inside an actor and serializes access to the store.

The lower-level wrappers mirror Wasmtime's C API more directly. `Config`,
`Store`, `Instance`, `InstancePre`, `Linker`, `Func`, `WasiConfig`, and
`Caller` are not `Sendable`; keep each store-bound object graph on one
serialized execution path and do not call into it concurrently.

Low-level handles should come from the same engine/store graph. For example, use
a `Module` with a `Store` created from the same `Engine`, and use store-bound
functions and instances only with the `Store` that owns them.

`Module.deserialize(engine:serialized:)`, `Module.deserialize(engine:data:)`,
and `Module.deserializeFile(engine:path:)` must only consume trusted artifacts
previously produced by `Module.serialize()` for a compatible Wasmtime engine,
version, target platform, and configuration. They are not safe APIs for loading
arbitrary user-controlled bytes.

`InstancePre` is created by `Linker.instantiatePre(module:)` after import
resolution has succeeded. It can instantiate into multiple compatible stores,
but each returned `Instance` is still bound to the store passed to
`InstancePre.instantiate(store:)`.

`Config` and `WasiConfig` are consumed by `Engine.init(config:)` and
`Store.setWasi(_:)` respectively. After consumption, using the same object again
is a programmer error. Prefer `EngineOptions` and `WasiOptions` for reusable,
sendable configuration values.

The public API is still intentionally small and pre-release in spirit. Public
enums such as `Value`, `ValueKind`, `WasmtimeError`, and `ExternKind` may gain
cases as more Wasmtime C API surface is wrapped.

Trap diagnostics are exposed as Swift value snapshots. `WasmFrame` and
`WasmTrace` copy the useful metadata from Wasmtime frames, including function
indexes, offsets, and optional names, but they do not expose borrowed frame
handles or store-bound frame instance handles. This keeps diagnostic values
`Sendable` and safe to retain after the original trap or error has been
released.

On iOS and iPadOS, `Engine` creation always targets Wasmtime's Pulley
interpreter (`pulley64`) so guest code runs without native JIT execution.
Cranelift remains present in the vendored C API so this package can still
compile WAT/Wasm inputs into Pulley bytecode on device.

## Importing From SwiftPM

Add the package dependency to your target. On iOS and iPadOS, the package links
the vendored `Wasmtime.xcframework` automatically.

On macOS, Linux, and Windows, also point your target at the vendored Wasmtime
library directory in SwiftPM's checkout. This mirrors the workaround used by
downstream SwiftPM packages that need to stay inside SwiftPM without a system
Wasmtime install.

SwiftPM may still warn about this package's own relative `Vendor/...` search
path when it is built as a dependency; the consumer target search path below is
the path that makes the final link step succeed for macOS, Linux, and Windows.

```swift
// swift-tools-version: 6.3

import PackageDescription

#if os(macOS)
let wasmtimeOS = "macos"
#elseif os(Linux)
let wasmtimeOS = "linux"
#elseif os(Windows)
let wasmtimeOS = "windows"
#else
#error("this manual linker search path is only needed on macOS, Linux, and Windows")
#endif

#if arch(arm64)
let wasmtimeArch = "aarch64"
#elseif arch(x86_64)
let wasmtimeArch = "x86_64"
#else
#error("swift-wasmtime currently supports arm64 and x86_64")
#endif

let wasmtimeVersion = "v45.0.0"
let wasmtimeLibraryPath = ".build/checkouts/swift-wasmtime/Vendor/Wasmtime/\(wasmtimeVersion)/\(wasmtimeArch)-\(wasmtimeOS)/lib"

let package = Package(
    name: "MyPackage",
    dependencies: [
        .package(
            url: "https://github.com/OpenCow42/swift-wasmtime.git",
            .upToNextMajor(from: "45.0.0")
        ),
    ],
    targets: [
        .target(
            name: "MyTarget",
            dependencies: [
                .product(name: "Wasmtime", package: "swift-wasmtime"),
            ],
            linkerSettings: [
                .unsafeFlags(["-L", wasmtimeLibraryPath]),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
```

For iOS and iPadOS consumer targets, omit the `linkerSettings` block above.

Then import and use the Swift module:

```swift
import Wasmtime

let engine = try Engine()
let store = try Store(engine: engine)
let module = try Module(
    engine: engine,
    wat: """
    (module
      (func (export "add") (param i32 i32) (result i32)
        local.get 0
        local.get 1
        i32.add))
    """
)

let instance = try Instance(store: store, module: module)
let add = try instance.exportedFunction(named: "add")
let result = try add.call([.i32(20), .i32(22)])
```

For code that crosses Swift concurrency domains, prefer the actor runtime:

```swift
import Wasmtime

let runtime = try WasmtimeRuntime()
let instance = try await runtime.instantiate(
    wat: """
    (module
      (func (export "add") (param i32 i32) (result i32)
        local.get 0
        local.get 1
        i32.add))
    """
)
let result = try await runtime.call("add", in: instance, arguments: [.i32(20), .i32(22)])
```

The actor runtime also exposes the package's WASI, linker, and early component
workflows without leaking store-bound handles across concurrency domains:

```swift
let wasi = WasiOptions(
    arguments: ["guest.wasm"],
    environment: ["LOG": "debug"],
    standardInputBytes: Array("request body".utf8),
    standardOutputHandler: { output in
        print(String(decoding: output, as: UTF8.self))
        return output.count
    }
)
try await runtime.setWasi(wasi)

let linked = try await runtime.instantiateWithLinker(
    module,
    defineWasi: true,
    defineUnknownImportsAsDefaultValues: false
)
try await runtime.call("_start", in: linked)

let hostBacked = try await runtime.instantiateWithLinker(
    module,
    hostFunctions: [
        RuntimeHostFunction(
            module: "host",
            name: "double",
            parameters: [.i32],
            results: [.i32]
        ) { arguments in
            guard case .i32(let value) = arguments[0] else {
                throw WasmtimeError.api(message: "unexpected argument", exitStatus: nil)
            }
            return [.i32(value * 2)]
        },
    ]
)
```

Low-level `Linker.defineFunction` callbacks are `@Sendable`. The `Caller`
value passed to a host callback is only valid for that callback invocation;
copy any data you need from guest memory before returning.

```swift
let componentRuntime = try WasmtimeRuntime(
    options: EngineOptions(isComponentModelEnabled: true)
)
let component = try await componentRuntime.compileComponent(wat: componentWat)
let componentInstance = try await componentRuntime.instantiateComponent(component)
try await componentRuntime.call("run", in: componentInstance)
```

## Version Tags

Git release tags use SwiftPM-friendly semantic versions without a leading `v`.
For example, this package tag is `45.0.0`, matching the vendored Wasmtime
`v45.0.0` release. Upstream Wasmtime still uses `v`-prefixed tags, so scripts
and vendored paths keep the upstream spelling where they interact with
Bytecode Alliance release assets.

## License

Swift Wasmtime is licensed under Apache-2.0 WITH LLVM-exception. The vendored
Wasmtime C API artifacts and headers are provided by the Bytecode Alliance
Wasmtime project under the same license. See `LICENSE` and
`THIRD_PARTY_NOTICES.md`.

## Build And Test

For local development with Xcode on macOS, keep Swift and Clang module caches
inside the workspace:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
swift test --disable-sandbox
```

iOS/iPadOS simulator test gate:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
xcodebuild test \
  -workspace .swiftpm/xcode/package.xcworkspace \
  -scheme Wasmtime \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath .build/xcode-derived
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
scripts/vendor-wasmtime.sh v45.0.0
```

The script downloads release metadata from GitHub, reads the official asset
digests, downloads the upstream C API archives where Wasmtime publishes them,
verifies SHA256 checksums, copies headers, preserves the upstream license, and
stores platform libraries under `Vendor/Wasmtime`.

Wasmtime does not publish iOS C API archives for `v45.0.0`, so on macOS the
script also downloads the matching source release, builds `aarch64-apple-ios`,
`aarch64-apple-ios-sim`, and `x86_64-apple-ios` static libraries with Xcode and
Rust, and packages them as `Vendor/Wasmtime/v45.0.0/Wasmtime.xcframework`.
