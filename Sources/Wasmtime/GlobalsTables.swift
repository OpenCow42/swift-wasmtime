import Foundation
@preconcurrency import CWasmtime

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

/// Immutable WebAssembly global type.
///
/// `GlobalType` is not store-bound and may be shared across Swift concurrency
/// domains. This wrapper currently supports numeric scalar value kinds only.
public final class GlobalType: @unchecked Sendable {
    let raw: OpaquePointer

    public let content: ValueKind
    public let isMutable: Bool

    public init(content: ValueKind, isMutable: Bool = false) throws {
        guard let valueType = wasm_valtype_new(content.wasmRawValue) else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasm_valtype_new returned nil")
        }
        let mutability = wasm_mutability_t(isMutable ? WASM_VAR.rawValue : WASM_CONST.rawValue)
        guard let raw = wasm_globaltype_new(valueType, mutability) else { // coverage:ignore defensive C allocation failure
            wasm_valtype_delete(valueType) // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasm_globaltype_new returned nil") // coverage:ignore defensive C allocation failure
        }
        self.raw = raw
        self.content = content
        self.isMutable = isMutable
    }

    init(raw: OpaquePointer) throws {
        guard let valueType = wasm_globaltype_content(raw) else { // coverage:ignore defensive C invariant
            wasm_globaltype_delete(raw) // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasm_globaltype_content returned nil") // coverage:ignore defensive C invariant
        }
        do {
            self.content = try ValueKind(rawValue: wasm_valtype_kind(valueType))
        } catch {
            wasm_globaltype_delete(raw)
            throw error
        }
        self.isMutable = wasm_globaltype_mutability(raw) == wasm_mutability_t(WASM_VAR.rawValue)
        self.raw = raw
    }

    deinit {
        wasm_globaltype_delete(raw)
    }
}

/// Store-bound WebAssembly global.
///
/// `Global` is not `Sendable`. Use it only on the serialized execution path
/// that owns its `Store`. This wrapper currently supports numeric scalar values
/// through `Value`.
public final class Global {
    let store: Store
    let raw: wasmtime_global_t

    public init(store: Store, type: GlobalType, value: Value) throws {
        var global = wasmtime_global_t()
        var rawValue = value.rawValue
        try WasmtimeError.throwIfNeeded(wasmtime_global_new(store.context, type.raw, &rawValue, &global))
        self.store = store
        self.raw = global
    }

    init(store: Store, raw: wasmtime_global_t) {
        self.store = store
        self.raw = raw
    }

    public func type() throws -> GlobalType {
        var global = raw
        guard let rawType = wasmtime_global_type(store.context, &global) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasmtime_global_type returned nil") // coverage:ignore defensive C invariant
        }
        return try GlobalType(raw: rawType)
    }

    public func get() throws -> Value {
        var global = raw
        var rawValue = wasmtime_val_t()
        wasmtime_global_get(store.context, &global, &rawValue)
        defer { wasmtime_val_unroot(&rawValue) }
        return try Value(rawValue: rawValue)
    }

    public func set(_ value: Value) throws {
        var global = raw
        var rawValue = value.rawValue
        try WasmtimeError.throwIfNeeded(wasmtime_global_set(store.context, &global, &rawValue))
    }
}

/// Reference kind stored by a WebAssembly table.
///
/// This package currently models `funcref` and `externref` table types. Full
/// non-null `externref` payloads are intentionally left for broader reference
/// value support.
public enum TableElementKind: Sendable, Equatable, CustomStringConvertible {
    case functionReference
    case externalReference
    case unknown(UInt8)

    var wasmRawValue: wasm_valkind_t {
        switch self {
        case .functionReference: wasm_valkind_t(WASM_FUNCREF.rawValue)
        case .externalReference: wasm_valkind_t(WASM_EXTERNREF.rawValue)
        case .unknown(let value): wasm_valkind_t(value)
        }
    }

    init(rawValue: wasm_valkind_t) {
        switch rawValue {
        case wasm_valkind_t(WASM_FUNCREF.rawValue):
            self = .functionReference
        case wasm_valkind_t(WASM_EXTERNREF.rawValue):
            self = .externalReference
        default:
            self = .unknown(UInt8(rawValue))
        }
    }

    public var description: String {
        switch self {
        case .functionReference: "funcref"
        case .externalReference: "externref"
        case .unknown(let value): "unknown(\(value))"
        }
    }
}

/// Table element values supported by this package's bounded table API.
///
/// `function` elements are store-bound through `Func`. Null `externref` values
/// are supported, but non-null host externrefs are not exposed yet.
public enum TableElement {
    case nullFunctionReference
    case function(Func)
    case nullExternalReference

    public var kind: TableElementKind {
        switch self {
        case .nullFunctionReference, .function:
            .functionReference
        case .nullExternalReference:
            .externalReference
        }
    }

    static func null(for kind: TableElementKind) throws -> TableElement {
        switch kind {
        case .functionReference:
            return .nullFunctionReference
        case .externalReference:
            return .nullExternalReference
        case .unknown(let value):
            throw WasmtimeError.unsupportedValueKind(Int(value))
        }
    }

    init(store: Store, rawValue: wasmtime_val_t) throws {
        var rawValue = rawValue
        switch rawValue.kind {
        case wasmtime_valkind_t(WASMTIME_FUNCREF):
            if wasmtime_funcref_is_null(&rawValue.of.funcref) {
                self = .nullFunctionReference
            } else {
                self = .function(Func(store: store, raw: rawValue.of.funcref))
            }
        case wasmtime_valkind_t(WASMTIME_EXTERNREF):
            guard wasmtime_externref_is_null(&rawValue.of.externref) else {
                throw WasmtimeError.unsupportedValueKind(Int(rawValue.kind))
            }
            self = .nullExternalReference
        default:
            throw WasmtimeError.unsupportedValueKind(Int(rawValue.kind))
        }
    }

    var rawValue: wasmtime_val_t {
        var raw = wasmtime_val_t()
        switch self {
        case .nullFunctionReference:
            raw.kind = wasmtime_valkind_t(WASMTIME_FUNCREF)
            wasmtime_funcref_set_null(&raw.of.funcref)
        case .function(let function):
            raw.kind = wasmtime_valkind_t(WASMTIME_FUNCREF)
            raw.of.funcref = function.raw
        case .nullExternalReference:
            raw.kind = wasmtime_valkind_t(WASMTIME_EXTERNREF)
            wasmtime_externref_set_null(&raw.of.externref)
        }
        return raw
    }
}

/// Immutable WebAssembly table type.
///
/// `TableType` is not store-bound and may be shared across Swift concurrency
/// domains. It describes the reference kind and element limits used when
/// creating a host table.
public final class TableType: @unchecked Sendable {
    let raw: OpaquePointer

    public let element: TableElementKind
    public let minimumElements: UInt32
    public let maximumElements: UInt32?

    public init(
        element: TableElementKind = .functionReference,
        minimumElements: UInt32,
        maximumElements: UInt32? = nil
    ) throws {
        guard case .unknown(let value) = element else {
            let valueType = wasm_valtype_new(element.wasmRawValue)
            guard let valueType else { // coverage:ignore defensive C allocation failure
                throw WasmtimeError.allocationFailed("wasm_valtype_new returned nil")
            }
            var limits = wasm_limits_t(min: minimumElements, max: maximumElements ?? wasm_limits_max_default)
            guard let raw = wasm_tabletype_new(valueType, &limits) else { // coverage:ignore defensive C allocation failure
                wasm_valtype_delete(valueType) // coverage:ignore defensive C allocation failure
                throw WasmtimeError.allocationFailed("wasm_tabletype_new returned nil") // coverage:ignore defensive C allocation failure
            }
            self.raw = raw
            self.element = element
            self.minimumElements = minimumElements
            self.maximumElements = maximumElements
            return
        }
        throw WasmtimeError.unsupportedValueKind(Int(value))
    }

    init(raw: OpaquePointer) throws {
        guard let elementType = wasm_tabletype_element(raw) else { // coverage:ignore defensive C invariant
            wasm_tabletype_delete(raw) // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasm_tabletype_element returned nil") // coverage:ignore defensive C invariant
        }
        guard let limits = wasm_tabletype_limits(raw) else { // coverage:ignore defensive C invariant
            wasm_tabletype_delete(raw) // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasm_tabletype_limits returned nil") // coverage:ignore defensive C invariant
        }
        self.raw = raw
        self.element = TableElementKind(rawValue: wasm_valtype_kind(elementType))
        self.minimumElements = limits.pointee.min
        self.maximumElements = limits.pointee.max == wasm_limits_max_default ? nil : limits.pointee.max
    }

    deinit {
        wasm_tabletype_delete(raw)
    }
}

/// Store-bound WebAssembly table.
///
/// `Table` is not `Sendable`. Use it only on the serialized execution path
/// that owns its `Store`. Arbitrary non-null `externref` payloads are not
/// modeled yet; use null externrefs or function references.
public final class Table {
    let store: Store
    let raw: wasmtime_table_t

    public init(store: Store, type: TableType, initialElement: TableElement? = nil) throws {
        let initialElement = try initialElement ?? TableElement.null(for: type.element)
        var rawElement = initialElement.rawValue
        var table = wasmtime_table_t()
        try WasmtimeError.throwIfNeeded(wasmtime_table_new(store.context, type.raw, &rawElement, &table))
        self.store = store
        self.raw = table
    }

    init(store: Store, raw: wasmtime_table_t) {
        self.store = store
        self.raw = raw
    }

    public func type() throws -> TableType {
        var table = raw
        guard let rawType = wasmtime_table_type(store.context, &table) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasmtime_table_type returned nil") // coverage:ignore defensive C invariant
        }
        return try TableType(raw: rawType)
    }

    public var size: UInt64 {
        var table = raw
        return wasmtime_table_size(store.context, &table)
    }

    public func get(index: UInt64) throws -> TableElement? {
        var table = raw
        var rawElement = wasmtime_val_t()
        guard wasmtime_table_get(store.context, &table, index, &rawElement) else {
            return nil
        }
        defer { wasmtime_val_unroot(&rawElement) }
        return try TableElement(store: store, rawValue: rawElement)
    }

    public func set(index: UInt64, to element: TableElement) throws {
        var table = raw
        var rawElement = element.rawValue
        try WasmtimeError.throwIfNeeded(wasmtime_table_set(store.context, &table, index, &rawElement))
    }

    @discardableResult
    public func grow(by deltaElements: UInt64, initialElement: TableElement? = nil) throws -> UInt64 {
        var table = raw
        let initialElement = try initialElement ?? TableElement.null(for: type().element)
        var rawElement = initialElement.rawValue
        var previousSize: UInt64 = 0
        try WasmtimeError.throwIfNeeded(
            wasmtime_table_grow(store.context, &table, deltaElements, &rawElement, &previousSize)
        )
        return previousSize
    }
}
