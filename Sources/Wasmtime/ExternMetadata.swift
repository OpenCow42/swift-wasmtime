import Foundation
@preconcurrency import CWasmtime

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

/// Store-bound extern item exported by an instance or found in a linker.
///
/// Functions, globals, tables, and memories have first-class wrappers today.
/// Other extern kinds are surfaced as `unsupported` until their safe Swift
/// wrappers land.
public enum Extern {
    case function(Func)
    case global(Global)
    case table(Table)
    case memory(Memory)
    case unsupported(ExternKind)

    public var kind: ExternKind {
        switch self {
        case .function: .function
        case .global: .global
        case .table: .table
        case .memory: .memory
        case .unsupported(let kind): kind
        }
    }

    init(store: Store, raw item: wasmtime_extern_t) {
        switch item.kind {
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_FUNC):
            self = .function(Func(store: store, raw: item.of.func))
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_GLOBAL):
            self = .global(Global(store: store, raw: item.of.global))
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_TABLE):
            self = .table(Table(store: store, raw: item.of.table))
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_MEMORY):
            self = .memory(Memory(store: store, raw: item.of.memory))
        default:
            self = .unsupported(ExternKind(rawValue: item.kind))
        }
    }
}

/// Store-bound export item returned when enumerating an instance's exports.
///
/// The `extern` value follows the same store-bound ownership rules as values
/// returned by `Instance.export(named:)`.
public struct InstanceExport {
    public let name: String
    public let extern: Extern

    public var kind: ExternKind {
        extern.kind
    }

    init(name: String, extern: Extern) {
        self.name = name
        self.extern = extern
    }
}

/// Compile-time type metadata for a core WebAssembly import or export.
///
/// These descriptors are immutable values and may be shared across Swift
/// concurrency domains. Function and global signatures are exposed only when
/// they use scalar value kinds already modeled by `ValueKind`; reference-heavy
/// types are reported as `unsupported` with their extern kind.
public enum ModuleExternType: Sendable, Equatable {
    case function(FunctionType)
    case global(ModuleGlobalType)
    case table(ModuleTableType)
    case memory(ModuleMemoryType)
    case unsupported(ExternKind)

    public var kind: ExternKind {
        switch self {
        case .function: .function
        case .global: .global
        case .table: .table
        case .memory: .memory
        case .unsupported(let kind): kind
        }
    }

    init(raw: OpaquePointer) throws {
        let kind = ExternKind(rawWasmValue: wasm_externtype_kind(raw))
        switch kind {
        case .function:
            guard let functionType = wasm_externtype_as_functype_const(raw) else { // coverage:ignore defensive C invariant
                throw WasmtimeError.allocationFailed("wasm_externtype_as_functype_const returned nil") // coverage:ignore defensive C invariant
            }
            do {
                self = .function(try FunctionType(raw: functionType))
            } catch WasmtimeError.unsupportedValueKind(_) {
                self = .unsupported(.function)
            }
        case .global:
            guard let globalType = wasm_externtype_as_globaltype_const(raw) else { // coverage:ignore defensive C invariant
                throw WasmtimeError.allocationFailed("wasm_externtype_as_globaltype_const returned nil") // coverage:ignore defensive C invariant
            }
            do {
                self = .global(try ModuleGlobalType(raw: globalType))
            } catch WasmtimeError.unsupportedValueKind(_) {
                self = .unsupported(.global)
            }
        case .table:
            guard let tableType = wasm_externtype_as_tabletype_const(raw) else { // coverage:ignore defensive C invariant
                throw WasmtimeError.allocationFailed("wasm_externtype_as_tabletype_const returned nil") // coverage:ignore defensive C invariant
            }
            self = .table(try ModuleTableType(raw: tableType))
        case .memory:
            guard let memoryType = wasm_externtype_as_memorytype_const(raw) else { // coverage:ignore defensive C invariant
                throw WasmtimeError.allocationFailed("wasm_externtype_as_memorytype_const returned nil") // coverage:ignore defensive C invariant
            }
            self = .memory(ModuleMemoryType(raw: memoryType))
        case .sharedMemory, .tag, .unknown:
            self = .unsupported(kind)
        }
    }
}

/// Compile-time scalar global type metadata for a module import or export.
public struct ModuleGlobalType: Sendable, Equatable {
    public var content: ValueKind
    public var isMutable: Bool

    public init(content: ValueKind, isMutable: Bool = false) {
        self.content = content
        self.isMutable = isMutable
    }

    init(raw: OpaquePointer) throws {
        guard let valueType = wasm_globaltype_content(raw) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasm_globaltype_content returned nil") // coverage:ignore defensive C invariant
        }
        self.content = try ValueKind(rawType: valueType)
        self.isMutable = wasm_globaltype_mutability(raw) == wasm_mutability_t(WASM_VAR.rawValue)
    }
}

/// Compile-time table type metadata for a module import or export.
public struct ModuleTableType: Sendable, Equatable {
    public var element: TableElementKind
    public var minimumElements: UInt32
    public var maximumElements: UInt32?

    public init(
        element: TableElementKind = .functionReference,
        minimumElements: UInt32,
        maximumElements: UInt32? = nil
    ) {
        self.element = element
        self.minimumElements = minimumElements
        self.maximumElements = maximumElements
    }

    init(raw: OpaquePointer) throws {
        guard let elementType = wasm_tabletype_element(raw) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasm_tabletype_element returned nil") // coverage:ignore defensive C invariant
        }
        guard let limits = wasm_tabletype_limits(raw) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasm_tabletype_limits returned nil") // coverage:ignore defensive C invariant
        }
        self.element = TableElementKind(rawValue: wasm_valtype_kind(elementType))
        self.minimumElements = limits.pointee.min
        self.maximumElements = limits.pointee.max == wasm_limits_max_default ? nil : limits.pointee.max
    }
}

/// Compile-time memory type metadata for a module import or export.
public struct ModuleMemoryType: Sendable, Equatable {
    public var minimumPages: UInt64
    public var maximumPages: UInt64?
    public var is64: Bool
    public var isShared: Bool
    public var pageSize: UInt64
    public var pageSizeLog2: UInt8

    public init(
        minimumPages: UInt64,
        maximumPages: UInt64? = nil,
        is64: Bool = false,
        isShared: Bool = false,
        pageSize: UInt64 = 65_536,
        pageSizeLog2: UInt8 = 16
    ) {
        self.minimumPages = minimumPages
        self.maximumPages = maximumPages
        self.is64 = is64
        self.isShared = isShared
        self.pageSize = pageSize
        self.pageSizeLog2 = pageSizeLog2
    }

    init(raw: OpaquePointer) {
        var maximum: UInt64 = 0
        self.minimumPages = wasmtime_memorytype_minimum(raw)
        self.maximumPages = wasmtime_memorytype_maximum(raw, &maximum) ? maximum : nil
        self.is64 = wasmtime_memorytype_is64(raw)
        self.isShared = wasmtime_memorytype_isshared(raw)
        self.pageSize = wasmtime_memorytype_page_size(raw)
        self.pageSizeLog2 = wasmtime_memorytype_page_size_log2(raw)
    }
}

/// Compile-time import descriptor for a core WebAssembly module.
public struct ModuleImport: Sendable, Equatable {
    public let module: String
    public let name: String
    public let type: ModuleExternType

    public var kind: ExternKind {
        type.kind
    }

    public init(module: String, name: String, type: ModuleExternType) {
        self.module = module
        self.name = name
        self.type = type
    }

    init(raw: OpaquePointer) throws {
        guard let module = wasm_importtype_module(raw) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasm_importtype_module returned nil") // coverage:ignore defensive C invariant
        }
        guard let name = wasm_importtype_name(raw) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasm_importtype_name returned nil") // coverage:ignore defensive C invariant
        }
        guard let type = wasm_importtype_type(raw) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasm_importtype_type returned nil") // coverage:ignore defensive C invariant
        }
        self.module = String(wasmByteVec: module.pointee)
        self.name = String(wasmByteVec: name.pointee)
        self.type = try ModuleExternType(raw: type)
    }
}

/// Compile-time export descriptor for a core WebAssembly module.
public struct ModuleExport: Sendable, Equatable {
    public let name: String
    public let type: ModuleExternType

    public var kind: ExternKind {
        type.kind
    }

    public init(name: String, type: ModuleExternType) {
        self.name = name
        self.type = type
    }

    init(raw: OpaquePointer) throws {
        guard let name = wasm_exporttype_name(raw) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasm_exporttype_name returned nil") // coverage:ignore defensive C invariant
        }
        guard let type = wasm_exporttype_type(raw) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasm_exporttype_type returned nil") // coverage:ignore defensive C invariant
        }
        self.name = String(wasmByteVec: name.pointee)
        self.type = try ModuleExternType(raw: type)
    }
}

/// Kind of an extern item exported by a Wasmtime instance or visible to a caller.
///
/// This enum may gain cases as more Wasmtime extern kinds are exposed.
public enum ExternKind: Sendable, Equatable, CustomStringConvertible {
    case function
    case global
    case table
    case memory
    case sharedMemory
    case tag
    case unknown(UInt8)

    init(rawValue: wasmtime_extern_kind_t) {
        switch rawValue {
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_FUNC): self = .function
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_GLOBAL): self = .global
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_TABLE): self = .table
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_MEMORY): self = .memory
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_SHAREDMEMORY): self = .sharedMemory
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_TAG): self = .tag
        default: self = .unknown(UInt8(rawValue))
        }
    }

    init(rawWasmValue: wasm_externkind_t) {
        switch rawWasmValue {
        case wasm_externkind_t(WASM_EXTERN_FUNC.rawValue): self = .function
        case wasm_externkind_t(WASM_EXTERN_GLOBAL.rawValue): self = .global
        case wasm_externkind_t(WASM_EXTERN_TABLE.rawValue): self = .table
        case wasm_externkind_t(WASM_EXTERN_MEMORY.rawValue): self = .memory
        case wasm_externkind_t(WASM_EXTERN_TAG.rawValue): self = .tag
        default: self = .unknown(UInt8(rawWasmValue))
        }
    }

    public var description: String {
        switch self {
        case .function: "func"
        case .global: "global"
        case .table: "table"
        case .memory: "memory"
        case .sharedMemory: "sharedMemory"
        case .tag: "tag"
        case .unknown(let value): "unknown(\(value))"
        }
    }
}
