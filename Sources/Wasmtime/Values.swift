import Foundation
@preconcurrency import CWasmtime

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

/// Scalar WebAssembly value kinds supported by this package's checked call API.
public enum ValueKind: Sendable, Equatable, CustomStringConvertible {
    case i32
    case i64
    case f32
    case f64

    var wasmRawValue: wasm_valkind_t {
        switch self {
        case .i32: wasm_valkind_t(WASM_I32.rawValue)
        case .i64: wasm_valkind_t(WASM_I64.rawValue)
        case .f32: wasm_valkind_t(WASM_F32.rawValue)
        case .f64: wasm_valkind_t(WASM_F64.rawValue)
        }
    }

    init(rawValue: wasm_valkind_t) throws {
        switch rawValue {
        case wasm_valkind_t(WASM_I32.rawValue):
            self = .i32
        case wasm_valkind_t(WASM_I64.rawValue):
            self = .i64
        case wasm_valkind_t(WASM_F32.rawValue):
            self = .f32
        case wasm_valkind_t(WASM_F64.rawValue):
            self = .f64
        default:
            throw WasmtimeError.unsupportedValueKind(Int(rawValue))
        }
    }

    public var description: String {
        switch self {
        case .i32: "i32"
        case .i64: "i64"
        case .f32: "f32"
        case .f64: "f64"
        }
    }
}

/// Scalar function signature for WebAssembly and host functions.
public struct FunctionType: Sendable, Equatable {
    public var parameters: [ValueKind]
    public var results: [ValueKind]

    public init(parameters: [ValueKind] = [], results: [ValueKind] = []) {
        self.parameters = parameters
        self.results = results
    }

    init(raw: OpaquePointer) throws {
        guard let params = wasm_functype_params(raw) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasm_functype_params returned nil") // coverage:ignore defensive C invariant
        }
        guard let results = wasm_functype_results(raw) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasm_functype_results returned nil") // coverage:ignore defensive C invariant
        }
        self.parameters = try Self.valueKinds(in: params)
        self.results = try Self.valueKinds(in: results)
    }

    func makeRaw() throws -> OpaquePointer {
        var params = try Self.makeValueTypeVector(parameters)
        var results = try Self.makeValueTypeVector(results)
        guard let type = wasm_functype_new(&params, &results) else { // coverage:ignore defensive C allocation failure
            wasm_valtype_vec_delete(&params) // coverage:ignore defensive C allocation failure
            wasm_valtype_vec_delete(&results) // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasm_functype_new returned nil") // coverage:ignore defensive C allocation failure
        }
        return type
    }

    private static func makeValueTypeVector(_ kinds: [ValueKind]) throws -> wasm_valtype_vec_t {
        var vector = wasm_valtype_vec_t()
        guard !kinds.isEmpty else {
            wasm_valtype_vec_new_empty(&vector)
            return vector
        }

        let types = try kinds.map { kind -> OpaquePointer? in
            guard let raw = wasm_valtype_new(kind.wasmRawValue) else { // coverage:ignore defensive C allocation failure
                throw WasmtimeError.allocationFailed("wasm_valtype_new returned nil") // coverage:ignore defensive C allocation failure
            }
            return raw
        }
        types.withUnsafeBufferPointer { buffer in
            wasm_valtype_vec_new(&vector, buffer.count, buffer.baseAddress)
        }
        return vector
    }

    private static func valueKinds(in vector: UnsafePointer<wasm_valtype_vec_t>) throws -> [ValueKind] {
        let count = Int(vector.pointee.size)
        guard count > 0 else {
            return []
        }
        guard let data = vector.pointee.data else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasm_valtype_vec_t data was nil") // coverage:ignore defensive C invariant
        }
        return try (0..<count).map { index in
            guard let valueType = data[index] else { // coverage:ignore defensive C invariant
                throw WasmtimeError.allocationFailed("wasm_valtype_vec_t element was nil") // coverage:ignore defensive C invariant
            }
            return try ValueKind(rawValue: wasm_valtype_kind(valueType))
        }
    }
}

/// Scalar WebAssembly values supported by this package's checked call API.
public enum Value: Sendable, Equatable, CustomStringConvertible {
    case i32(Int32)
    case i64(Int64)
    case f32(Float)
    case f64(Double)

    var rawValue: wasmtime_val_t {
        var raw = wasmtime_val_t()
        switch self {
        case .i32(let value):
            raw.kind = wasmtime_valkind_t(WASMTIME_I32)
            raw.of.i32 = value
        case .i64(let value):
            raw.kind = wasmtime_valkind_t(WASMTIME_I64)
            raw.of.i64 = value
        case .f32(let value):
            raw.kind = wasmtime_valkind_t(WASMTIME_F32)
            raw.of.f32 = value
        case .f64(let value):
            raw.kind = wasmtime_valkind_t(WASMTIME_F64)
            raw.of.f64 = value
        }
        return raw
    }

    public var kind: ValueKind {
        switch self {
        case .i32: .i32
        case .i64: .i64
        case .f32: .f32
        case .f64: .f64
        }
    }

    init(rawValue: wasmtime_val_t) throws {
        switch rawValue.kind {
        case wasmtime_valkind_t(WASMTIME_I32):
            self = .i32(rawValue.of.i32)
        case wasmtime_valkind_t(WASMTIME_I64):
            self = .i64(rawValue.of.i64)
        case wasmtime_valkind_t(WASMTIME_F32):
            self = .f32(rawValue.of.f32)
        case wasmtime_valkind_t(WASMTIME_F64):
            self = .f64(rawValue.of.f64)
        default:
            throw WasmtimeError.unsupportedValueKind(Int(rawValue.kind))
        }
    }

    public var description: String {
        switch self {
        case .i32(let value): "i32(\(value))"
        case .i64(let value): "i64(\(value))"
        case .f32(let value): "f32(\(value))"
        case .f64(let value): "f64(\(value))"
        }
    }
}

/// Utility for compiling WebAssembly text format into binary bytes.
public enum WasmText {
    public static func compile(_ wat: String) throws -> [UInt8] {
        var output = wasm_byte_vec_t()
        let error = wat.withCString { cWat in
            wasmtime_wat2wasm(cWat, strlen(cWat), &output)
        }
        try WasmtimeError.throwIfNeeded(error)
        defer { wasm_byte_vec_delete(&output) }
        return output.withUnsafeBytes { Array($0) }
    }
}
