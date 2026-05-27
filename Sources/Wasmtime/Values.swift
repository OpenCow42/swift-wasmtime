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
    case v128

    var wasmRawValue: wasm_valkind_t {
        switch self {
        case .i32: wasm_valkind_t(WASM_I32.rawValue)
        case .i64: wasm_valkind_t(WASM_I64.rawValue)
        case .f32: wasm_valkind_t(WASM_F32.rawValue)
        case .f64: wasm_valkind_t(WASM_F64.rawValue)
        case .v128: wasm_valkind_t(WASMTIME_V128)
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
        case wasm_valkind_t(WASMTIME_V128):
            self = .v128
        default:
            throw WasmtimeError.unsupportedValueKind(Int(rawValue))
        }
    }

    init(rawType: OpaquePointer) throws {
        try self.init(rawValue: Self.rawValueKind(for: rawType))
    }

    public var description: String {
        switch self {
        case .i32: "i32"
        case .i64: "i64"
        case .f32: "f32"
        case .f64: "f64"
        case .v128: "v128"
        }
    }

    func makeRawValueType() throws -> OpaquePointer {
        if self == .v128 {
            guard let raw = wasmtime_wasm_valtype_v128() else { // coverage:ignore defensive C allocation failure
                throw WasmtimeError.allocationFailed("wasmtime_wasm_valtype_v128 returned nil") // coverage:ignore defensive C allocation failure
            }
            return raw
        }
        guard let raw = wasm_valtype_new(wasmRawValue) else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasm_valtype_new returned nil") // coverage:ignore defensive C allocation failure
        }
        return raw
    }

    private static func rawValueKind(for raw: OpaquePointer) -> wasm_valkind_t {
        var type = wasmtime_valtype_t()
        wasmtime_valtype_new(raw, &type)
        defer { wasmtime_valtype_delete(&type) }

        switch type.kind {
        case wasmtime_valtype_kind_t(WASMTIME_VALTYPE_KIND_I32):
            return wasm_valkind_t(WASM_I32.rawValue)
        case wasmtime_valtype_kind_t(WASMTIME_VALTYPE_KIND_I64):
            return wasm_valkind_t(WASM_I64.rawValue)
        case wasmtime_valtype_kind_t(WASMTIME_VALTYPE_KIND_F32):
            return wasm_valkind_t(WASM_F32.rawValue)
        case wasmtime_valtype_kind_t(WASMTIME_VALTYPE_KIND_F64):
            return wasm_valkind_t(WASM_F64.rawValue)
        case wasmtime_valtype_kind_t(WASMTIME_VALTYPE_KIND_V128):
            return wasm_valkind_t(WASMTIME_V128)
        default:
            return wasm_valtype_kind(raw)
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
            try kind.makeRawValueType()
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
            return try ValueKind(rawType: valueType)
        }
    }
}

/// A 128-bit SIMD WebAssembly value.
///
/// Wasmtime stores `v128` values as 16 little-endian bytes. The canonical Swift
/// representation is `SIMD16<UInt8>`; lane-specific SIMD views reinterpret
/// those same bytes.
public struct V128: Sendable, Equatable, CustomStringConvertible {
    public var bytes: SIMD16<UInt8>

    public init(bytes: SIMD16<UInt8>) {
        self.bytes = bytes
    }

    public init(littleEndianBytes bytes: [UInt8]) throws {
        guard bytes.count == 16 else {
            throw WasmtimeError.api(message: "v128 requires exactly 16 bytes", exitStatus: nil)
        }
        self.bytes = SIMD16<UInt8>(bytes)
    }

    public init(i8x16 lanes: SIMD16<Int8>) {
        self.bytes = unsafeBitCast(lanes, to: SIMD16<UInt8>.self)
    }

    public init(i16x8 lanes: SIMD8<Int16>) {
        self.bytes = unsafeBitCast(lanes, to: SIMD16<UInt8>.self)
    }

    public init(i32x4 lanes: SIMD4<Int32>) {
        self.bytes = unsafeBitCast(lanes, to: SIMD16<UInt8>.self)
    }

    public init(i64x2 lanes: SIMD2<Int64>) {
        self.bytes = unsafeBitCast(lanes, to: SIMD16<UInt8>.self)
    }

    public init(f32x4 lanes: SIMD4<Float>) {
        self.bytes = unsafeBitCast(lanes, to: SIMD16<UInt8>.self)
    }

    public init(f64x2 lanes: SIMD2<Double>) {
        self.bytes = unsafeBitCast(lanes, to: SIMD16<UInt8>.self)
    }

    public var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: bytes) { Array($0) }
    }

    public var i8x16: SIMD16<Int8> {
        unsafeBitCast(bytes, to: SIMD16<Int8>.self)
    }

    public var i16x8: SIMD8<Int16> {
        unsafeBitCast(bytes, to: SIMD8<Int16>.self)
    }

    public var i32x4: SIMD4<Int32> {
        unsafeBitCast(bytes, to: SIMD4<Int32>.self)
    }

    public var i64x2: SIMD2<Int64> {
        unsafeBitCast(bytes, to: SIMD2<Int64>.self)
    }

    public var f32x4: SIMD4<Float> {
        unsafeBitCast(bytes, to: SIMD4<Float>.self)
    }

    public var f64x2: SIMD2<Double> {
        unsafeBitCast(bytes, to: SIMD2<Double>.self)
    }

    public var description: String {
        "v128(\(littleEndianBytes))"
    }

    init(rawValue: wasmtime_v128) {
        self.bytes = withUnsafeBytes(of: rawValue) { rawBytes in
            SIMD16<UInt8>(Array(rawBytes))
        }
    }

    func write(to rawValue: inout wasmtime_v128) {
        withUnsafeMutableBytes(of: &rawValue) { destination in
            withUnsafeBytes(of: bytes) { source in
                destination.copyMemory(from: source)
            }
        }
    }
}

/// WebAssembly values supported by this package's checked call API.
public enum Value: Sendable, Equatable, CustomStringConvertible {
    case i32(Int32)
    case i64(Int64)
    case f32(Float)
    case f64(Double)
    case v128(V128)

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
        case .v128(let value):
            raw.kind = wasmtime_valkind_t(WASMTIME_V128)
            value.write(to: &raw.of.v128)
        }
        return raw
    }

    public var kind: ValueKind {
        switch self {
        case .i32: .i32
        case .i64: .i64
        case .f32: .f32
        case .f64: .f64
        case .v128: .v128
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
        case wasmtime_valkind_t(WASMTIME_V128):
            self = .v128(V128(rawValue: rawValue.of.v128))
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
        case .v128(let value): value.description
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
