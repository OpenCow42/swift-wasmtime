import Foundation
@preconcurrency import CWasmtime

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

/// Store-bound core WebAssembly instance.
///
/// `Instance` is not `Sendable`. Use it only on the serialized execution path
/// that owns its `Store`, or call through `WasmtimeRuntime`.
public final class Instance {
    private let store: Store
    let raw: wasmtime_instance_t

    public init(store: Store, module: Module) throws {
        var instance = wasmtime_instance_t()
        var trap: OpaquePointer?
        let error = wasmtime_instance_new(store.context, module.raw, nil, 0, &instance, &trap)
        try WasmtimeError.throwIfNeeded(error, trap: trap)
        self.store = store
        self.raw = instance
    }

    init(store: Store, raw: wasmtime_instance_t) {
        self.store = store
        self.raw = raw
    }

    public func export(named name: String) throws -> Extern {
        var item = wasmtime_extern_t()
        var instance = raw
        let found = name.withCString { cName in
            wasmtime_instance_export_get(store.context, &instance, cName, strlen(cName), &item)
        }
        guard found else {
            throw WasmtimeError.missingExport(name)
        }
        defer { wasmtime_extern_delete(&item) }

        return Extern(store: store, raw: item)
    }

    public func export(at index: Int) throws -> InstanceExport? {
        guard index >= 0 else {
            return nil
        }

        var item = wasmtime_extern_t()
        var instance = raw
        var rawName: UnsafeMutablePointer<CChar>?
        var rawNameLength = 0
        let found = wasmtime_instance_export_nth(
            store.context,
            &instance,
            index,
            &rawName,
            &rawNameLength,
            &item
        )
        guard found else {
            return nil
        }
        defer { wasmtime_extern_delete(&item) }
        guard let rawName else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasmtime_instance_export_nth returned nil export name") // coverage:ignore defensive C invariant
        }

        let nameBytes = UnsafeBufferPointer(
            start: UnsafeRawPointer(rawName).assumingMemoryBound(to: UInt8.self),
            count: rawNameLength
        )
        let name = String(decoding: nameBytes, as: UTF8.self)
        return InstanceExport(name: name, extern: Extern(store: store, raw: item))
    }

    public func exports() throws -> [InstanceExport] {
        var exports: [InstanceExport] = []
        var index = 0
        while let item = try export(at: index) {
            exports.append(item)
            index += 1
        }
        return exports
    }

    public func exportedFunction(named name: String) throws -> Func {
        let item = try export(named: name)
        guard case .function(let function) = item else {
            throw WasmtimeError.wrongExportKind(name: name, expected: "func", actual: item.kind.description)
        }

        return function
    }

    public func exportedGlobal(named name: String) throws -> Global {
        let item = try export(named: name)
        guard case .global(let global) = item else {
            throw WasmtimeError.wrongExportKind(name: name, expected: "global", actual: item.kind.description)
        }

        return global
    }

    public func exportedTable(named name: String) throws -> Table {
        let item = try export(named: name)
        guard case .table(let table) = item else {
            throw WasmtimeError.wrongExportKind(name: name, expected: "table", actual: item.kind.description)
        }

        return table
    }

    public func exportedMemory(named name: String = "memory") throws -> Memory {
        let item = try export(named: name)
        guard case .memory(let memory) = item else {
            throw WasmtimeError.wrongExportKind(name: name, expected: "memory", actual: item.kind.description)
        }

        return memory
    }
}

/// A linked core WebAssembly module ready for repeated store instantiation.
///
/// `InstancePre` is not `Sendable`. It owns Wasmtime pre-instantiation state
/// produced by a `Linker`, and each `instantiate(store:)` call creates an
/// `Instance` bound to the provided `Store`.
public final class InstancePre {
    private let engine: Engine
    let raw: OpaquePointer

    init(engine: Engine, raw: OpaquePointer) {
        self.engine = engine
        self.raw = raw
    }

    public func instantiate(store: Store) throws -> Instance {
        var instance = wasmtime_instance_t()
        var trap: OpaquePointer?
        let error = wasmtime_instance_pre_instantiate(raw, store.context, &instance, &trap)
        try WasmtimeError.throwIfNeeded(error, trap: trap)
        return Instance(store: store, raw: instance)
    }

    public func module() throws -> Module {
        guard let rawModule = wasmtime_instance_pre_module(raw) else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasmtime_instance_pre_module returned nil") // coverage:ignore defensive C allocation failure
        }
        return Module(engine: engine, raw: rawModule)
    }

    deinit {
        wasmtime_instance_pre_delete(raw)
    }
}

/// Temporary host-callback caller context.
///
/// `Caller` is only valid during the host function invocation that receives it.
/// It expires when the callback returns. Copy data out of guest memory before
/// returning, and do not store `Caller` for later use.
public final class Caller {
    private let state: CallerState

    init(raw: OpaquePointer?) {
        self.state = CallerState(raw: raw)
    }

    /// Returns the kind of an export visible from the calling instance.
    ///
    /// Throws `WasmtimeError.callerExpired` if used after the host callback has
    /// returned.
    public func exportKind(named name: String) throws -> ExternKind? {
        guard let raw = try state.currentRaw() else {
            return nil
        }

        var item = wasmtime_extern_t()
        let found = name.withCString { cName in
            wasmtime_caller_export_get(raw, cName, strlen(cName), &item)
        }
        guard found else {
            return nil
        }
        defer { wasmtime_extern_delete(&item) }
        return ExternKind(rawValue: item.kind)
    }

    /// Copies bytes from an exported memory visible from the calling instance.
    ///
    /// Returns `nil` when the export is missing or is not a memory. Throws when
    /// the caller has expired or the requested range is out of bounds.
    public func readMemory(named name: String = "memory", offset: Int, length: Int) throws -> [UInt8]? {
        guard offset >= 0, length >= 0 else {
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: length, memorySize: 0)
        }
        guard let raw = try state.currentRaw(), var memory = exportedMemory(named: name, caller: raw) else {
            return nil
        }
        let context = wasmtime_caller_context(raw)
        let memorySize = wasmtime_memory_data_size(context, &memory)
        guard offset <= memorySize, length <= memorySize - offset else {
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: length, memorySize: memorySize)
        }
        guard let data = wasmtime_memory_data(context, &memory) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: length, memorySize: memorySize)
        }
        return Array(UnsafeBufferPointer(start: data.advanced(by: offset), count: length))
    }

    /// Writes bytes to an exported memory visible from the calling instance.
    ///
    /// Returns `false` when the export is missing or is not a memory. Throws
    /// when the caller has expired or the requested range is out of bounds.
    public func writeMemory(named name: String = "memory", offset: Int, bytes: [UInt8]) throws -> Bool {
        guard offset >= 0 else {
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: bytes.count, memorySize: 0)
        }
        guard let raw = try state.currentRaw(), var memory = exportedMemory(named: name, caller: raw) else {
            return false
        }
        let context = wasmtime_caller_context(raw)
        let memorySize = wasmtime_memory_data_size(context, &memory)
        guard offset <= memorySize, bytes.count <= memorySize - offset else {
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: bytes.count, memorySize: memorySize)
        }
        guard let data = wasmtime_memory_data(context, &memory) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: bytes.count, memorySize: memorySize)
        }
        bytes.withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                data.advanced(by: offset).update(from: baseAddress, count: buffer.count)
            }
        }
        return true
    }

    private func exportedMemory(named name: String, caller: OpaquePointer) -> wasmtime_memory_t? {
        var item = wasmtime_extern_t()
        let found = name.withCString { cName in
            wasmtime_caller_export_get(caller, cName, strlen(cName), &item)
        }
        guard found else {
            return nil
        }
        defer { wasmtime_extern_delete(&item) }
        guard item.kind == WASMTIME_EXTERN_MEMORY else { // coverage:ignore wasmtime_caller_export_get currently returns only memories
            return nil // coverage:ignore wasmtime_caller_export_get currently returns only memories
        }
        return item.of.memory
    }

    func invalidate() {
        state.invalidate()
    }
}

/// Store-bound WebAssembly component instance.
///
/// `ComponentInstance` is not `Sendable`. Use it only on the serialized
/// execution path that owns its `Store`, or call through `WasmtimeRuntime`.
public final class ComponentInstance {
    private let store: Store
    let raw: wasmtime_component_instance_t

    init(store: Store, raw: wasmtime_component_instance_t) {
        self.store = store
        self.raw = raw
    }

    public func exportedFunction(named name: String) throws -> ComponentFunction {
        var instance = raw
        let exportIndex = name.withCString { cName in
            wasmtime_component_instance_get_export_index(&instance, store.context, nil, cName, strlen(cName))
        }
        guard let exportIndex else {
            throw WasmtimeError.missingExport(name)
        }
        defer { wasmtime_component_export_index_delete(exportIndex) }

        var function = wasmtime_component_func_t()
        guard wasmtime_component_instance_get_func(&instance, store.context, exportIndex, &function) else {
            throw WasmtimeError.wrongExportKind(name: name, expected: "func", actual: "component export")
        }

        return ComponentFunction(store: store, raw: function)
    }
}

private final class CallerState {
    private let lock = NSLock()
    private var raw: OpaquePointer?
    private var isExpired = false

    init(raw: OpaquePointer?) {
        self.raw = raw
    }

    func currentRaw() throws -> OpaquePointer? {
        try lock.withLock {
            guard !isExpired else {
                throw WasmtimeError.callerExpired
            }
            return raw
        }
    }

    func invalidate() {
        lock.withLock {
            isExpired = true
            raw = nil
        }
    }
}
