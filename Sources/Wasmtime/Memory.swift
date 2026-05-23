import Foundation
@preconcurrency import CWasmtime

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

/// Store-level resource limits.
///
/// Each `nil` value keeps Wasmtime's default for that limit. Limits apply only
/// to future resource creation or growth.
public struct ResourceLimits: Sendable, Equatable {
    public var memorySizeBytes: Int64?
    public var tableElements: Int64?
    public var instances: Int64?
    public var tables: Int64?
    public var memories: Int64?

    public init(
        memorySizeBytes: Int64? = nil,
        tableElements: Int64? = nil,
        instances: Int64? = nil,
        tables: Int64? = nil,
        memories: Int64? = nil
    ) {
        self.memorySizeBytes = memorySizeBytes
        self.tableElements = tableElements
        self.instances = instances
        self.tables = tables
        self.memories = memories
    }
}

/// Immutable WebAssembly linear-memory type.
///
/// `MemoryType` is not store-bound and may be shared across Swift concurrency
/// domains. It describes the page limits and memory64/shared/custom-page-size
/// settings used when creating a host memory.
public final class MemoryType: @unchecked Sendable {
    let raw: OpaquePointer

    public init(
        minimumPages: UInt64,
        maximumPages: UInt64? = nil,
        is64: Bool = false,
        isShared: Bool = false,
        pageSizeLog2: UInt8 = 16
    ) throws {
        var raw: OpaquePointer?
        try WasmtimeError.throwIfNeeded(
            wasmtime_memorytype_new(
                minimumPages,
                maximumPages != nil,
                maximumPages ?? 0,
                is64,
                isShared,
                pageSizeLog2,
                &raw
            )
        )
        guard let raw else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasmtime_memorytype_new returned nil without an error") // coverage:ignore defensive C invariant
        }
        self.raw = raw
    }

    init(raw: OpaquePointer) {
        self.raw = raw
    }

    public var minimumPages: UInt64 {
        wasmtime_memorytype_minimum(raw)
    }

    public var maximumPages: UInt64? {
        var maximum: UInt64 = 0
        guard wasmtime_memorytype_maximum(raw, &maximum) else {
            return nil
        }
        return maximum
    }

    public var is64: Bool {
        wasmtime_memorytype_is64(raw)
    }

    public var isShared: Bool {
        wasmtime_memorytype_isshared(raw)
    }

    public var pageSize: UInt64 {
        wasmtime_memorytype_page_size(raw)
    }

    public var pageSizeLog2: UInt8 {
        wasmtime_memorytype_page_size_log2(raw)
    }

    deinit {
        wasm_memorytype_delete(raw)
    }
}

/// Store-bound WebAssembly linear memory.
///
/// `Memory` is not `Sendable`. Use it only on the serialized execution path
/// that owns its `Store`, or access memory through `WasmtimeRuntime`.
public final class Memory {
    let store: Store
    let raw: wasmtime_memory_t

    public init(store: Store, type: MemoryType) throws {
        var memory = wasmtime_memory_t()
        try WasmtimeError.throwIfNeeded(wasmtime_memory_new(store.context, type.raw, &memory))
        self.store = store
        self.raw = memory
    }

    init(store: Store, raw: wasmtime_memory_t) {
        self.store = store
        self.raw = raw
    }

    public func type() throws -> MemoryType {
        var memory = raw
        guard let rawType = wasmtime_memory_type(store.context, &memory) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasmtime_memory_type returned nil") // coverage:ignore defensive C invariant
        }
        return MemoryType(raw: rawType)
    }

    public var size: UInt64 {
        var memory = raw
        return wasmtime_memory_size(store.context, &memory)
    }

    public var dataSize: Int {
        var memory = raw
        return wasmtime_memory_data_size(store.context, &memory)
    }

    public var pageSize: UInt64 {
        var memory = raw
        return wasmtime_memory_page_size(store.context, &memory)
    }

    public var pageSizeLog2: UInt8 {
        var memory = raw
        return wasmtime_memory_page_size_log2(store.context, &memory)
    }

    public func read(offset: Int, length: Int) throws -> [UInt8] {
        guard offset >= 0, length >= 0 else {
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: length, memorySize: 0)
        }
        let memorySize = dataSize
        guard offset <= memorySize, length <= memorySize - offset else {
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: length, memorySize: memorySize)
        }
        guard length > 0 else {
            return []
        }
        var memory = raw
        guard let data = wasmtime_memory_data(store.context, &memory) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: length, memorySize: memorySize)
        }
        return Array(UnsafeBufferPointer(start: data.advanced(by: offset), count: length))
    }

    public func write(offset: Int, bytes: [UInt8]) throws {
        guard offset >= 0 else {
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: bytes.count, memorySize: 0)
        }
        let memorySize = dataSize
        guard offset <= memorySize, bytes.count <= memorySize - offset else {
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: bytes.count, memorySize: memorySize)
        }
        guard !bytes.isEmpty else {
            return
        }
        var memory = raw
        guard let data = wasmtime_memory_data(store.context, &memory) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: bytes.count, memorySize: memorySize)
        }
        bytes.withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                data.advanced(by: offset).update(from: baseAddress, count: buffer.count)
            }
        }
    }

    @discardableResult
    public func grow(by deltaPages: UInt64) throws -> UInt64 {
        var previousSize: UInt64 = 0
        var memory = raw
        try WasmtimeError.throwIfNeeded(wasmtime_memory_grow(store.context, &memory, deltaPages, &previousSize))
        return previousSize
    }
}
