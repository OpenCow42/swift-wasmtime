import Foundation
@preconcurrency import CWasmtime

#if os(Linux)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Low-level name-based linker for core WebAssembly modules.
///
/// `Linker` is not `Sendable`. Use it on a serialized execution path with
/// modules, stores, instances, and functions from the same engine/store graph.
public final class Linker {
    private let engine: Engine
    let raw: OpaquePointer

    public init(engine: Engine) throws {
        guard let raw = wasmtime_linker_new(engine.raw) else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasmtime_linker_new returned nil")
        }
        self.engine = engine
        self.raw = raw
    }

    private init(engine: Engine, raw: OpaquePointer, allowsShadowing: Bool) {
        self.engine = engine
        self.raw = raw
        self.allowsShadowing = allowsShadowing
    }

    public var allowsShadowing: Bool = false {
        didSet {
            wasmtime_linker_allow_shadowing(raw, allowsShadowing)
        }
    }

    public func clone() throws -> Linker {
        guard let cloned = wasmtime_linker_clone(raw) else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasmtime_linker_clone returned nil")
        }

        return Linker(engine: engine, raw: cloned, allowsShadowing: allowsShadowing)
    }

    public func defineWasi() throws {
        try WasmtimeError.throwIfNeeded(wasmtime_linker_define_wasi(raw))
    }

    public func defineUnknownImportsAsTraps(module: Module) throws {
        try WasmtimeError.throwIfNeeded(wasmtime_linker_define_unknown_imports_as_traps(raw, module.raw))
    }

    public func defineUnknownImportsAsDefaultValues(store: Store, module: Module) throws {
        try WasmtimeError.throwIfNeeded(wasmtime_linker_define_unknown_imports_as_default_values(raw, store.context, module.raw))
    }

    public func get(store: Store, module: String, name: String) -> Extern? {
        var item = wasmtime_extern_t()
        let found = module.withCString { cModule in
            name.withCString { cName in
                wasmtime_linker_get(raw, store.context, cModule, strlen(cModule), cName, strlen(cName), &item)
            }
        }
        guard found else {
            return nil
        }
        defer { wasmtime_extern_delete(&item) }
        return Extern(store: store, raw: item)
    }

    public func defaultFunction(store: Store, moduleName: String) throws -> Func {
        var function = wasmtime_func_t()
        try moduleName.withCString { cName in
            try WasmtimeError.throwIfNeeded(
                wasmtime_linker_get_default(raw, store.context, cName, strlen(cName), &function)
            )
        }

        return Func(store: store, raw: function)
    }

    public func defineInstance(store: Store, name: String, instance: Instance) throws {
        var instance = instance.raw
        try name.withCString { cName in
            try WasmtimeError.throwIfNeeded(
                wasmtime_linker_define_instance(raw, store.context, cName, strlen(cName), &instance)
            )
        }
    }

    public func defineModule(store: Store, name: String, module: Module) throws {
        try name.withCString { cName in
            try WasmtimeError.throwIfNeeded(
                wasmtime_linker_module(raw, store.context, cName, strlen(cName), module.raw)
            )
        }
    }

    /// Defines an already-created store-bound host function in this linker.
    ///
    /// The function remains bound to the store that created it. The linker uses
    /// that store automatically when registering the extern.
    public func define(module: String, name: String, function: Func) throws {
        var item = wasmtime_extern_t()
        item.kind = wasmtime_extern_kind_t(WASMTIME_EXTERN_FUNC)
        item.of.func = function.raw
        try module.withCString { cModule in
            try name.withCString { cName in
                try WasmtimeError.throwIfNeeded(
                    wasmtime_linker_define(raw, function.store.context, cModule, strlen(cModule), cName, strlen(cName), &item)
                )
            }
        }
    }

    /// Defines an already-created store-bound memory in this linker.
    ///
    /// The memory remains bound to the store that created it. The linker uses
    /// that store automatically when registering the extern.
    public func define(module: String, name: String, memory: Memory) throws {
        var item = wasmtime_extern_t()
        item.kind = wasmtime_extern_kind_t(WASMTIME_EXTERN_MEMORY)
        item.of.memory = memory.raw
        try module.withCString { cModule in
            try name.withCString { cName in
                try WasmtimeError.throwIfNeeded(
                    wasmtime_linker_define(raw, memory.store.context, cModule, strlen(cModule), cName, strlen(cName), &item)
                )
            }
        }
    }

    /// Defines an already-created store-bound global in this linker.
    ///
    /// The global remains bound to the store that created it. The linker uses
    /// that store automatically when registering the extern.
    public func define(module: String, name: String, global: Global) throws {
        var item = wasmtime_extern_t()
        item.kind = wasmtime_extern_kind_t(WASMTIME_EXTERN_GLOBAL)
        item.of.global = global.raw
        try module.withCString { cModule in
            try name.withCString { cName in
                try WasmtimeError.throwIfNeeded(
                    wasmtime_linker_define(raw, global.store.context, cModule, strlen(cModule), cName, strlen(cName), &item)
                )
            }
        }
    }

    /// Defines an already-created store-bound table in this linker.
    ///
    /// The table remains bound to the store that created it. The linker uses
    /// that store automatically when registering the extern.
    public func define(module: String, name: String, table: Table) throws {
        var item = wasmtime_extern_t()
        item.kind = wasmtime_extern_kind_t(WASMTIME_EXTERN_TABLE)
        item.of.table = table.raw
        try module.withCString { cModule in
            try name.withCString { cName in
                try WasmtimeError.throwIfNeeded(
                    wasmtime_linker_define(raw, table.store.context, cModule, strlen(cModule), cName, strlen(cName), &item)
                )
            }
        }
    }

    /// Defines a store-independent host function in this linker.
    ///
    /// The callback is `@Sendable` because linker-defined functions can be used
    /// by multiple stores. Capture only thread-safe state or serialize access in
    /// the callback.
    public func defineFunction(
        module: String,
        name: String,
        type: FunctionType,
        _ body: @escaping HostFunction
    ) throws {
        let rawType = try type.makeRaw()
        defer { wasm_functype_delete(rawType) }
        let box = HostFunctionBox(type: type, body: body)
        let data = Unmanaged.passRetained(box).toOpaque()
        let error = module.withCString { cModule in
            name.withCString { cName in
                wasmtime_linker_define_func(
                    raw,
                    cModule,
                    strlen(cModule),
                    cName,
                    strlen(cName),
                    rawType,
                    hostFunctionCallback,
                    data,
                    hostFunctionFinalizer
                )
            }
        }
        if let error {
            throw WasmtimeError.fromOwned(error)
        }
    }

    public func defineFunction(
        module: String,
        name: String,
        parameters: [ValueKind] = [],
        results: [ValueKind] = [],
        _ body: @escaping HostFunction
    ) throws {
        try defineFunction(
            module: module,
            name: name,
            type: FunctionType(parameters: parameters, results: results),
            body
        )
    }

    public func instantiate(store: Store, module: Module) throws -> Instance {
        var instance = wasmtime_instance_t()
        var trap: OpaquePointer?
        let error = wasmtime_linker_instantiate(raw, store.context, module.raw, &instance, &trap)
        try WasmtimeError.throwIfNeeded(error, trap: trap)
        return Instance(store: store, raw: instance)
    }

    public func instantiatePre(module: Module) throws -> InstancePre {
        var instancePre: OpaquePointer?
        let error = wasmtime_linker_instantiate_pre(raw, module.raw, &instancePre)
        try WasmtimeError.throwIfNeeded(error)
        guard let instancePre else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasmtime_linker_instantiate_pre returned nil without an error") // coverage:ignore defensive C invariant
        }
        return InstancePre(engine: engine, raw: instancePre)
    }

    deinit {
        wasmtime_linker_delete(raw)
    }
}

/// Low-level name-based linker for WebAssembly components.
///
/// `ComponentLinker` is not `Sendable`. Use it on a serialized execution path
/// with components and stores from the same engine graph.
public final class ComponentLinker {
    private let engine: Engine
    let raw: OpaquePointer

    public init(engine: Engine) throws {
        guard let raw = wasmtime_component_linker_new(engine.raw) else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasmtime_component_linker_new returned nil")
        }
        self.engine = engine
        self.raw = raw
    }

    public var allowsShadowing: Bool = false {
        didSet {
            wasmtime_component_linker_allow_shadowing(raw, allowsShadowing)
        }
    }

    public func addWasiP2() throws {
        try WasmtimeError.throwIfNeeded(wasmtime_component_linker_add_wasip2(raw))
    }

    public func addWasiHTTP() throws {
        try WasmtimeError.throwIfNeeded(wasmtime_component_linker_add_wasi_http(raw))
    }

    public func instantiate(store: Store, component: Component) throws -> ComponentInstance {
        var instance = wasmtime_component_instance_t()
        let error = wasmtime_component_linker_instantiate(raw, store.context, component.raw, &instance)
        try WasmtimeError.throwIfNeeded(error)
        return ComponentInstance(store: store, raw: instance)
    }

    deinit {
        wasmtime_component_linker_delete(raw)
    }
}
