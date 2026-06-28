# Swift Wasmtime Roadmap

This roadmap tracks missing Swift API coverage compared with the vendored
Wasmtime C API in `Sources/CWasmtime/include` for Wasmtime `v46.0.1`.

Swift Wasmtime is not trying to mirror every C function one-for-one. The goal is
to grow a small, memory-safe, Swift 6-friendly API while making intentional gaps
visible before public release.

## Priority Guide

- `P1`: Important before broad public use.
- `P2`: Important for serious embedders, but not required for the current small
  runtime surface.
- `P3`: Useful for tooling, completeness, or specialized workloads.
- `P4`: Advanced or niche API families that should wait until there is clear
  demand.

## Current Covered Surface

- Engine/config/store/module/instance/function/linker basics.
- Swift concurrency surface through `EngineOptions`, `WasiOptions`, and the
  `WasmtimeRuntime` actor.
- Core module compilation from WAT, bytes, and `Data`, validation of Wasm bytes
  and `Data`, shallow module cloning, and trusted compiled-artifact
  serialization/deserialization.
- Core module import/export type metadata through `Module.imports()` and
  `Module.exports()`.
- Direct and linker-based instantiation, linker cloning, and default function
  lookup for named modules.
- Linker pre-instantiation with reusable `InstancePre` handles and module clone
  inspection.
- Exported core function lookup and checked calls for `i32`, `i64`, `f32`,
  `f64`, and SIMD-backed `v128`.
- Function signature introspection through `Func.type()` and `FunctionType`.
- Host functions through `Func`, `Linker.defineFunction`, and
  `RuntimeHostFunction`.
- General extern lookup through `Extern`, `Instance.export(named:)`,
  `Instance.export(at:)`, `Instance.exports()`, and
  `Linker.get(store:module:name:)`. Functions, globals, tables, and memories
  have first-class wrappers; unsupported externs preserve their `ExternKind`.
- `Caller` export-kind lookup and exported-memory read/write helpers during
  host callback execution.
- Linear memory types, host-created memories, exported memory lookup,
  store-bound memory imports in `Linker`, copy-based memory reads/writes,
  memory growth, and actor-isolated memory helpers.
- Resource controls for fuel, epoch deadlines, epoch deadline callbacks, store
  resource limits, explicit store GC, engine epoch increments, and maximum Wasm
  stack configuration.
- WASI configuration from `wasi.h`: arguments, environment, inherited stdio,
  stdin bytes/files, stdout/stderr files, stdout/stderr callbacks, preopened
  directories, inherited network access, and IP name lookup.
- WASI HTTP store initialization and component linker registration.
- Early component model support: compile component, instantiate component,
  register WASIp2/WASI HTTP, and call zero-parameter, zero-result exported
  component functions.
- Trap/error conversion for normal calls and instantiation failures.

## P1 - Public Embedding Safety

No P1 API coverage gaps are currently tracked. The initial public embedding
safety gap, resource limits and interruption, is now covered by
`InterruptionOptions`, `ResourceLimits`, low-level `Store`/`Engine` methods, and
actor-isolated `WasmtimeRuntime` methods.

## P2 - Core Extern Coverage

### General Extern Wrappers

The package exposes generic extern lookup, including ordered instance export
enumeration, but tags and shared memories do not have first-class safe wrappers
yet.

- Public `Linker.define` overloads for tags.
- Shared-memory externs are tracked separately below.

### Globals

Numeric scalar and `v128` globals are covered by `GlobalType`, `Global`,
`Instance.exportedGlobal(named:)`, `Extern.global`, and
`Linker.define(module:name:global:)`.

Remaining global-related gaps:

- Reference-typed global values, pending broader reference value modeling.

### Tables

Table metadata, size, growth, exported table lookup, linker-defined tables,
function references, and null `funcref`/`externref` elements are covered by
`TableElementKind`, `TableElement`, `TableType`, `Table`,
`Instance.exportedTable(named:)`, `Extern.table`, and
`Linker.define(module:name:table:)`.

Remaining table-related gaps:

- Non-null host `externref` payload creation and inspection.
- Broader GC/reference table element kinds beyond `funcref` and `externref`.

### Tags And Exceptions

Missing tag and exception support:

- `wasmtime_tag_new`
- `wasmtime_tag_type`
- `wasmtime_tag_eq`
- `wasmtime_exn_type_new`
- `wasmtime_exn_type_delete`
- `wasmtime_exn_type_copy`
- `wasmtime_exn_type_tag_type`
- `wasmtime_exnref_new`
- `wasmtime_exnref_clone`
- `wasmtime_exnref_unroot`
- `wasmtime_exnref_tag`
- `wasmtime_exnref_field_count`
- `wasmtime_exnref_field`
- `wasmtime_context_has_exception`
- `wasmtime_context_take_exception`
- `wasmtime_context_set_exception`

## P2 - Function And Value Coverage

### Broader Value Types

Swift Wasmtime currently supports scalar numeric values and `v128`.

Missing value kinds and value wrappers include:

- `funcref`
- `externref`
- `anyref`
- `eqref`
- `i31`
- `structref`
- `arrayref`
- `exnref`

Related C API families:

- `wasmtime/val.h`
- split GC/reference headers such as `wasmtime/externref.h`,
  `wasmtime/anyref.h`, `wasmtime/structref.h`, `wasmtime/arrayref.h`, and
  `wasmtime/exnref.h`
- Standard value/type helpers from `wasm.h`.

### Function Type Introspection

The package can build function types and inspect `Func` signatures through
`Func.type()` and `FunctionType`.

Remaining function type gaps:

- Reference-typed function signatures, pending broader reference value modeling.

### Unchecked Calls

Wasmtime exposes unchecked function calls and unchecked host callbacks:

- `wasmtime_func_call_unchecked`
- `wasmtime_func_new_unchecked`
- `wasmtime_linker_define_func_unchecked`

These should remain unimplemented until a strong Swift safety story exists.

## P2 - Linker Completeness

### Core Linker APIs

Covered low-level pre-instantiation surface:

- `wasmtime_linker_instantiate_pre`
- `wasmtime_instance_pre_instantiate`
- `wasmtime_instance_pre_module`
- `wasmtime_instance_pre_delete`

Remaining linker work:

- Actor-managed pre-instantiation APIs, only if they can preserve store safety.

## P2 - Component Model Parity

The current component support is intentionally early. Wasmtime exposes a much
larger component API.

### Component Values

Missing component value support:

- Primitive component values.
- Strings.
- Lists.
- Records.
- Tuples.
- Variants.
- Enums.
- Options.
- Results.
- Flags.
- Maps.
- Futures and streams.
- Component resources.

Related C API families:

- `wasmtime/component/val.h`
- `wasmtime/component/types/val.h`
- `wasmtime/component/types/resource.h`

### Component Function Calls

Current component calls only support zero parameters and zero results.

Missing:

- Component function type introspection.
- Typed parameter and result conversion.
- Multi-result handling.
- Rich error reporting for type mismatches.
- `wasmtime_component_func_type`

`wasmtime_component_func_post_return` is deprecated upstream and should not be
wrapped unless compatibility requires it.

### Component Linker Host Support

Missing component linker APIs:

- `wasmtime_component_linker_root`
- `wasmtime_component_linker_define_unknown_imports_as_traps`
- `wasmtime_component_linker_instance_add_instance`
- `wasmtime_component_linker_instance_add_module`
- `wasmtime_component_linker_instance_add_func`
- `wasmtime_component_linker_instance_add_resource`
- `wasmtime_component_linker_instance_delete`

This is the component-model equivalent of full host function support and will
need a careful Swift ownership/lifetime design.

### Component Type Introspection

Missing component type inspection:

- Component import/export counts.
- Component import/export lookup by name.
- Component import/export iteration.
- Instance type export inspection.
- Module type import/export inspection.
- Component item wrappers.

Related C API families:

- `wasmtime/component/types/component.h`
- `wasmtime/component/types/instance.h`
- `wasmtime/component/types/module.h`
- `wasmtime/component/types/func.h`

## P3 - Module And Component Artifact Workflows

### Core Module Artifacts

Missing module APIs:

- `wasmtime_module_image_range`

Covered module APIs:

- `wasmtime_module_serialize`
- `wasmtime_module_deserialize`
- `wasmtime_module_deserialize_file`

The deserialize APIs are documented as trusted-input only, matching Wasmtime's C
API safety notes.

### Component Artifacts

Missing component APIs:

- `wasmtime_component_serialize`
- `wasmtime_component_deserialize`
- `wasmtime_component_deserialize_file`
- `wasmtime_component_clone`
- `wasmtime_component_type`
- `wasmtime_component_get_export_index`
- `wasmtime_component_export_index_clone`
- `wasmtime_component_export_index_delete`

## P3 - Error, Trap, And Diagnostics

Diagnostics are intentionally exposed as Swift value snapshots rather than raw
Wasmtime frame handles:

- Raw Wasmtime error/trap constructors are intentionally not public today; use
  Swift value helpers such as `Trap.host(message:)`,
  `Trap.instruction(code:message:)`, `WasmtimeError.hostTrap(message:)`, and
  `WasmtimeError.hostError(message:exitStatus:)`.
- `wasm_frame_copy` is not public because Swift callers receive owned
  `WasmFrame` values, not borrowed frame handles that need copying.
- `wasm_frame_instance` is not public because it would expose a store-bound
  instance handle through a diagnostic frame and reintroduce lifetime/aliasing
  concerns that `WasmFrame` is designed to avoid.

## P3 - Configuration Completeness

The current config surface is useful but incomplete. Missing config knobs:

- `wasmtime_config_cache_config_load`
- `wasmtime_config_wasm_threads_set`
- `wasmtime_config_wasm_stack_switching_set`
- Component-model async config knobs, pending a Swift async component API.

The remaining entries are intentionally deferred because cache loading returns
errors and needs path/default-cache semantics, while Wasm threads and stack
switching are gated by the vendored Wasmtime build/compiler configuration.

## P3 - Shared Memory

Missing shared-memory support:

- `wasmtime_sharedmemory_new`
- `wasmtime_sharedmemory_clone`
- `wasmtime_sharedmemory_delete`
- `wasmtime_sharedmemory_type`
- `wasmtime_sharedmemory_data`
- `wasmtime_sharedmemory_data_size`
- `wasmtime_sharedmemory_size`
- `wasmtime_sharedmemory_grow`

This should wait until normal `Memory` has a safe Swift design.

## P3 - Async Support

Wasmtime exposes async APIs, but Swift Wasmtime currently uses Swift actors for
serialization rather than Wasmtime async stores/calls.

Missing async APIs:

- `wasmtime_func_call_async`
- `wasmtime_linker_define_async_func`
- `wasmtime_linker_instantiate_async`
- `wasmtime_instance_pre_instantiate_async`
- `wasmtime_call_future_poll`
- `wasmtime_call_future_delete`
- `wasmtime_context_fuel_async_yield_interval`
- `wasmtime_context_epoch_deadline_async_yield_and_update`
- `wasmtime_config_host_stack_creator_set`
- Component async config, instantiation, function call, and component linker
  callback APIs added in Wasmtime v45.

These should only be wrapped if the package commits to a real Swift async
integration story.

## P4 - Advanced Allocation And Profiling

### Pooling Allocator

Missing pooling allocator configuration:

- `wasmtime_pooling_allocation_config_new`
- `wasmtime_pooling_allocation_config_delete`
- Pooling allocator property setters from `wasmtime/config.h`.

### Custom Memory Creator

Missing host memory creator support:

- `wasmtime_config_host_memory_creator_set`
- `wasmtime_memory_creator_t`
- `wasmtime_linear_memory_t`

These callbacks must be thread-safe and are easy to expose unsafely from Swift,
so they should be delayed until there is a concrete use case.

### Guest Profiling

Missing profiling APIs:

- `wasmtime_guestprofiler_new`
- `wasmtime_guestprofiler_sample`
- `wasmtime_guestprofiler_finish`
- `wasmtime_guestprofiler_delete`

## P4 - Standard Wasm C API Parity

The vendored headers include the standard `wasm.h` API in addition to
Wasmtime-specific APIs. Swift Wasmtime currently wraps the Wasmtime-specific C
API directly and should not chase full `wasm.h` parity unless a user-facing
Swift design calls for it.

Potential areas:

- Standard `wasm_module_t`, `wasm_instance_t`, `wasm_func_t` wrappers.
- Standard import/export type wrappers.
- Standard `wasm_extern_t` conversion APIs.
- Standard limits, table, global, memory, and tag type helpers.
- `wasm_foreign_t`.

## Documentation Tasks

- Keep `README.md` scoped to the currently supported API.
- Add focused examples as new API families land.
- Add a compatibility table for Wasmtime C API families once this roadmap starts
  being implemented.
- Document any unsafe/raw-pointer escape hatches separately from the main safe
  Swift API.
