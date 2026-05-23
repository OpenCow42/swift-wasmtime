# Swift Wasmtime Roadmap

This roadmap tracks missing Swift API coverage compared with the vendored
Wasmtime C API in `Sources/CWasmtime/include` for Wasmtime `v44.0.1`.

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
- Core module compilation from WAT, bytes, and `Data`.
- Direct and linker-based instantiation.
- Exported core function lookup and checked scalar calls for `i32`, `i64`,
  `f32`, and `f64`.
- Host functions through `Func`, `Linker.defineFunction`, and
  `RuntimeHostFunction`.
- General extern lookup through `Extern`, `Instance.export(named:)`, and
  `Linker.get(store:module:name:)`. Functions and memories have first-class
  wrappers; unsupported externs preserve their `ExternKind`.
- `Caller` export-kind lookup and exported-memory read/write helpers during
  host callback execution.
- Linear memory types, host-created memories, exported memory lookup,
  store-bound memory imports in `Linker`, copy-based memory reads/writes,
  memory growth, and actor-isolated memory helpers.
- Resource controls for fuel, epoch deadlines, epoch deadline callbacks, store
  resource limits, explicit store GC, engine epoch increments, and maximum Wasm
  stack configuration.
- WASI configuration from `wasi.h`: arguments, environment, inherited stdio,
  stdin bytes/files, stdout/stderr files, stdout/stderr callbacks, and preopened
  directories.
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

The package exposes generic extern lookup, but globals, tables, tags, and shared
memories do not have first-class safe wrappers yet.

- Public `Linker.define` overloads for globals, tables, and tags.
- Public export-by-index support via `wasmtime_instance_export_nth`.
- Shared-memory externs are tracked separately below.

### Globals

Missing global type and global wrappers:

- `wasmtime_global_new`
- `wasmtime_global_type`
- `wasmtime_global_get`
- `wasmtime_global_set`
- Standard C API global type helpers from `wasm.h`.

### Tables

Missing table type and table wrappers:

- `wasmtime_table_new`
- `wasmtime_table_type`
- `wasmtime_table_get`
- `wasmtime_table_set`
- `wasmtime_table_size`
- `wasmtime_table_grow`
- Standard C API table type helpers from `wasm.h`.

### Tags And Exceptions

Missing tag and exception support:

- `wasmtime_tag_new`
- `wasmtime_tag_type`
- `wasmtime_tag_eq`
- `wasmtime_exn_new`
- `wasmtime_exn_delete`
- `wasmtime_exn_tag`
- `wasmtime_exn_field_count`
- `wasmtime_exn_field`
- `wasmtime_context_has_exception`
- `wasmtime_context_take_exception`
- `wasmtime_context_set_exception`

## P2 - Function And Value Coverage

### Broader Value Types

Swift Wasmtime currently supports scalar numeric values only.

Missing value kinds and value wrappers include:

- `funcref`
- `externref`
- `anyref`
- `eqref`
- `i31`
- `structref`
- `arrayref`
- `exnref`
- `v128`, if a stable Swift representation is chosen.

Related C API families:

- `wasmtime/val.h`
- `wasmtime/gc.h`
- Standard value/type helpers from `wasm.h`.

### Function Type Introspection

The package can build function types, but does not expose public introspection
over imported/exported function signatures.

- Public function type wrapper.
- Parameter/result inspection.
- Export/import type inspection integration.

### Unchecked Calls

Wasmtime exposes unchecked function calls and unchecked host callbacks:

- `wasmtime_func_call_unchecked`
- `wasmtime_func_new_unchecked`
- `wasmtime_linker_define_func_unchecked`

These should remain unimplemented until a strong Swift safety story exists.

## P2 - Linker Completeness

### Core Linker APIs

Missing linker surface:

- `wasmtime_linker_clone`
- `wasmtime_linker_get_default`
- `wasmtime_linker_instantiate_pre`
- `wasmtime_instance_pre_instantiate`
- `wasmtime_instance_pre_module`
- `wasmtime_instance_pre_delete`

Likely Swift shape:

- `Linker.clone()`
- `Linker.defaultFunction(...) -> Func`
- `InstancePre` as a non-`Sendable` low-level wrapper.
- Actor-managed pre-instantiation APIs only if they can preserve store safety.

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

- `wasmtime_module_validate`
- `wasmtime_module_imports`
- `wasmtime_module_exports`
- `wasmtime_module_serialize`
- `wasmtime_module_deserialize`
- `wasmtime_module_deserialize_file`
- `wasmtime_module_image_range`
- `wasmtime_module_clone`

The deserialize APIs must be documented as trusted-input only, matching
Wasmtime's C API safety notes.

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

Missing diagnostics APIs:

- `wasmtime_error_new`
- `wasmtime_error_wasm_trace`
- `wasmtime_trap_new`
- `wasmtime_trap_new_code`
- `wasm_trap_origin`
- `wasm_trap_trace`
- `wasm_frame_copy`
- `wasm_frame_instance`
- `wasm_frame_func_index`
- `wasm_frame_func_offset`
- `wasm_frame_module_offset`
- `wasmtime_frame_func_name`
- `wasmtime_frame_module_name`

Likely Swift shape:

- Add `WasmFrame` and `WasmTrace` sendable value types.
- Include trace information in `Trap` and `WasmtimeError.api` where available.
- Consider public helpers for creating host-side Wasmtime errors only when
  needed by host callbacks.

## P3 - Configuration Completeness

The current config surface is useful but incomplete. Missing config knobs:

- `wasmtime_config_cache_config_load`
- `wasmtime_config_wasm_threads_set`
- `wasmtime_config_shared_memory_set`
- `wasmtime_config_wasm_tail_call_set`
- `wasmtime_config_wasm_reference_types_set`
- `wasmtime_config_wasm_function_references_set`
- `wasmtime_config_wasm_gc_set`
- `wasmtime_config_gc_support_set`
- `wasmtime_config_wasm_bulk_memory_set`
- `wasmtime_config_wasm_multi_value_set`
- `wasmtime_config_wasm_multi_memory_set`
- `wasmtime_config_wasm_memory64_set`
- `wasmtime_config_wasm_wide_arithmetic_set`
- `wasmtime_config_wasm_exceptions_set`
- `wasmtime_config_wasm_custom_page_sizes_set`
- `wasmtime_config_wasm_stack_switching_set`
- `wasmtime_config_cranelift_debug_verifier_set`
- `wasmtime_config_cranelift_nan_canonicalization_set`
- `wasmtime_config_profiler_set`
- `wasmtime_config_native_unwind_info_set`
- `wasmtime_config_macos_use_mach_ports_set`
- `wasmtime_config_memory_init_cow_set`

Swift should add these through both `Config` and `EngineOptions` when they are
simple value settings.

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
- Document any trusted-input requirements for deserialize APIs.
- Document any unsafe/raw-pointer escape hatches separately from the main safe
  Swift API.
