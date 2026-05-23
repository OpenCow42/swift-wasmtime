import Foundation
@preconcurrency import CWasmtime

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

/// Compiled core WebAssembly module.
///
/// Modules are immutable after compilation and may be shared across Swift
/// concurrency domains. Instantiate them with stores created from the same
/// `Engine`.
public final class Module: @unchecked Sendable {
    private let engine: Engine
    let raw: OpaquePointer

    public static func validate(engine: Engine, wasm: [UInt8]) throws {
        try validate(engine: engine, bytes: wasm)
    }

    public static func validate(engine: Engine, data: Data) throws {
        try validate(engine: engine, bytes: Array(data))
    }

    public convenience init(engine: Engine, wasm: [UInt8]) throws {
        try self.init(engine: engine, bytes: wasm)
    }

    public convenience init(engine: Engine, data: Data) throws {
        try self.init(engine: engine, bytes: Array(data))
    }

    public convenience init(engine: Engine, wat: String) throws {
        try self.init(engine: engine, bytes: WasmText.compile(wat))
    }

    private init(engine: Engine, bytes: [UInt8]) throws {
        var module: OpaquePointer?
        let error = bytes.withUnsafeBufferPointer { buffer in
            wasmtime_module_new(engine.raw, buffer.baseAddress, buffer.count, &module)
        }
        try WasmtimeError.throwIfNeeded(error)
        guard let module else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasmtime_module_new returned nil without an error")
        }
        self.engine = engine
        self.raw = module
    }

    init(engine: Engine, raw: OpaquePointer) {
        self.engine = engine
        self.raw = raw
    }

    public func clone() throws -> Module {
        guard let clone = wasmtime_module_clone(raw) else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasmtime_module_clone returned nil")
        }
        return Module(engine: engine, raw: clone)
    }

    /// Serializes this compiled module into Wasmtime's native artifact format.
    ///
    /// The returned bytes are only suitable for
    /// `Module.deserialize(engine:serialized:)` with a compatible Wasmtime
    /// engine, version, target platform, and configuration.
    public func serialize() throws -> [UInt8] {
        var output = wasm_byte_vec_t()
        try WasmtimeError.throwIfNeeded(wasmtime_module_serialize(raw, &output))
        defer { wasm_byte_vec_delete(&output) }
        return output.withUnsafeBytes { Array($0) }
    }

    /// Deserializes a compiled module artifact previously produced by Wasmtime.
    ///
    /// Only pass trusted bytes that were produced by `Module.serialize()` from
    /// a compatible Wasmtime engine, version, target platform, and
    /// configuration. Wasmtime's deserialize API is not safe for arbitrary
    /// user-controlled input.
    public static func deserialize(engine: Engine, serialized bytes: [UInt8]) throws -> Module {
        var module: OpaquePointer?
        let error = bytes.withUnsafeBufferPointer { buffer in
            wasmtime_module_deserialize(engine.raw, buffer.baseAddress, buffer.count, &module)
        }
        try WasmtimeError.throwIfNeeded(error)
        guard let module else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasmtime_module_deserialize returned nil without an error")
        }
        return Module(engine: engine, raw: module)
    }

    /// Deserializes a compiled module artifact from `Data`.
    ///
    /// Only pass trusted data that was produced by `Module.serialize()` from a
    /// compatible Wasmtime engine, version, target platform, and configuration.
    /// Wasmtime's deserialize API is not safe for arbitrary user-controlled
    /// input.
    public static func deserialize(engine: Engine, data: Data) throws -> Module {
        try data.withUnsafeBytes { buffer in
            var module: OpaquePointer?
            let error = wasmtime_module_deserialize(
                engine.raw,
                buffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                buffer.count,
                &module
            )
            try WasmtimeError.throwIfNeeded(error)
            guard let module else { // coverage:ignore defensive C invariant
                throw WasmtimeError.allocationFailed("wasmtime_module_deserialize returned nil without an error")
            }
            return Module(engine: engine, raw: module)
        }
    }

    /// Deserializes a compiled module artifact from an on-disk file.
    ///
    /// Only point this at trusted files containing bytes produced by
    /// `Module.serialize()` from a compatible Wasmtime engine, version, target
    /// platform, and configuration. Wasmtime's deserialize API is not safe for
    /// arbitrary user-controlled input.
    public static func deserializeFile(engine: Engine, path: String) throws -> Module {
        var module: OpaquePointer?
        let error = path.withCString { path in
            wasmtime_module_deserialize_file(engine.raw, path, &module)
        }
        try WasmtimeError.throwIfNeeded(error)
        guard let module else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasmtime_module_deserialize_file returned nil without an error")
        }
        return Module(engine: engine, raw: module)
    }

    public func imports() throws -> [ModuleImport] {
        var vector = wasm_importtype_vec_t()
        wasmtime_module_imports(raw, &vector)
        defer { wasm_importtype_vec_delete(&vector) }

        guard vector.size > 0 else {
            return []
        }
        guard let data = vector.data else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasm_importtype_vec_t data was nil") // coverage:ignore defensive C invariant
        }
        return try (0..<Int(vector.size)).map { index in
            guard let item = data[index] else { // coverage:ignore defensive C invariant
                throw WasmtimeError.allocationFailed("wasm_importtype_vec_t element was nil") // coverage:ignore defensive C invariant
            }
            return try ModuleImport(raw: item)
        }
    }

    public func exports() throws -> [ModuleExport] {
        var vector = wasm_exporttype_vec_t()
        wasmtime_module_exports(raw, &vector)
        defer { wasm_exporttype_vec_delete(&vector) }

        guard vector.size > 0 else {
            return []
        }
        guard let data = vector.data else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasm_exporttype_vec_t data was nil") // coverage:ignore defensive C invariant
        }
        return try (0..<Int(vector.size)).map { index in
            guard let item = data[index] else { // coverage:ignore defensive C invariant
                throw WasmtimeError.allocationFailed("wasm_exporttype_vec_t element was nil") // coverage:ignore defensive C invariant
            }
            return try ModuleExport(raw: item)
        }
    }

    deinit {
        wasmtime_module_delete(raw)
    }

    private static func validate(engine: Engine, bytes: [UInt8]) throws {
        let error = bytes.withUnsafeBufferPointer { buffer in
            wasmtime_module_validate(engine.raw, buffer.baseAddress, buffer.count)
        }
        try WasmtimeError.throwIfNeeded(error)
    }
}

/// Compiled WebAssembly component.
///
/// Components are immutable after compilation and may be shared across Swift
/// concurrency domains. Instantiate them with stores created from the same
/// `Engine`.
public final class Component: @unchecked Sendable {
    private let engine: Engine
    let raw: OpaquePointer

    public convenience init(engine: Engine, wasm: [UInt8]) throws {
        try self.init(engine: engine, bytes: wasm)
    }

    public convenience init(engine: Engine, data: Data) throws {
        try self.init(engine: engine, bytes: Array(data))
    }

    public convenience init(engine: Engine, wat: String) throws {
        try self.init(engine: engine, bytes: WasmText.compile(wat))
    }

    private init(engine: Engine, bytes: [UInt8]) throws {
        var component: OpaquePointer?
        let error = bytes.withUnsafeBufferPointer { buffer in
            wasmtime_component_new(engine.raw, buffer.baseAddress, buffer.count, &component)
        }
        try WasmtimeError.throwIfNeeded(error)
        guard let component else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasmtime_component_new returned nil without an error")
        }
        self.engine = engine
        self.raw = component
    }

    deinit {
        wasmtime_component_delete(raw)
    }
}
