import Foundation
@preconcurrency import CWasmtime

#if os(Linux)
import Glibc
#else
import Darwin
#endif

public final class Engine: @unchecked Sendable {
    let raw: OpaquePointer

    public init() throws {
        guard let raw = wasm_engine_new() else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasm_engine_new returned nil")
        }
        self.raw = raw
    }

    deinit {
        wasm_engine_delete(raw)
    }
}

public final class Store {
    private let engine: Engine
    let raw: OpaquePointer
    var context: OpaquePointer {
        wasmtime_store_context(raw)
    }

    public init(engine: Engine) throws {
        guard let raw = wasmtime_store_new(engine.raw, nil, nil) else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasmtime_store_new returned nil")
        }
        self.engine = engine
        self.raw = raw
    }

    public func setWasi(_ config: WasiConfig) throws {
        try WasmtimeError.throwIfNeeded(wasmtime_context_set_wasi(context, config.release()))
    }

    deinit {
        wasmtime_store_delete(raw)
    }
}

public final class Module: @unchecked Sendable {
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

    deinit {
        wasmtime_module_delete(raw)
    }
}

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

    public func exportedFunction(named name: String) throws -> Func {
        var item = wasmtime_extern_t()
        var instance = raw
        let found = name.withCString { cName in
            wasmtime_instance_export_get(store.context, &instance, cName, strlen(cName), &item)
        }
        guard found else {
            throw WasmtimeError.missingExport(name)
        }
        defer { wasmtime_extern_delete(&item) }

        guard item.kind == WASMTIME_EXTERN_FUNC else {
            throw WasmtimeError.wrongExportKind(name: name, expected: "func", actual: ExternKind(rawValue: item.kind).description)
        }

        return Func(store: store, raw: item.of.func)
    }
}

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

    public var allowsShadowing: Bool = false {
        didSet {
            wasmtime_linker_allow_shadowing(raw, allowsShadowing)
        }
    }

    public func defineWasi() throws {
        try WasmtimeError.throwIfNeeded(wasmtime_linker_define_wasi(raw))
    }

    public func instantiate(store: Store, module: Module) throws -> Instance {
        var instance = wasmtime_instance_t()
        var trap: OpaquePointer?
        let error = wasmtime_linker_instantiate(raw, store.context, module.raw, &instance, &trap)
        try WasmtimeError.throwIfNeeded(error, trap: trap)
        return Instance(store: store, raw: instance)
    }

    deinit {
        wasmtime_linker_delete(raw)
    }
}

public final class Func {
    private let store: Store
    let raw: wasmtime_func_t

    init(store: Store, raw: wasmtime_func_t) {
        self.store = store
        self.raw = raw
    }

    public func call(_ arguments: [Value] = []) throws -> [Value] {
        let resultCount = self.resultCount()
        let rawArguments = arguments.map(\.rawValue)
        var rawResults = Array(repeating: wasmtime_val_t(), count: resultCount)
        var trap: OpaquePointer?
        var function = raw

        let error = rawArguments.withUnsafeBufferPointer { argsBuffer in
            rawResults.withUnsafeMutableBufferPointer { resultsBuffer in
                wasmtime_func_call(
                    store.context,
                    &function,
                    argsBuffer.baseAddress,
                    argsBuffer.count,
                    resultsBuffer.baseAddress,
                    resultsBuffer.count,
                    &trap
                )
            }
        }
        try WasmtimeError.throwIfNeeded(error, trap: trap)
        defer {
            for index in rawResults.indices {
                wasmtime_val_unroot(&rawResults[index])
            }
        }
        return try rawResults.map(Value.init(rawValue:))
    }

    private func resultCount() -> Int {
        var function = raw
        guard let type = wasmtime_func_type(store.context, &function) else { // coverage:ignore defensive C invariant
            return 0
        }
        defer { wasm_functype_delete(type) }
        guard let results = wasm_functype_results(type) else { // coverage:ignore defensive C invariant
            return 0
        }
        return results.pointee.size
    }
}

public final class WasiConfig {
    private var raw: OpaquePointer?

    public init() throws {
        guard let raw = wasi_config_new() else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasi_config_new returned nil")
        }
        self.raw = raw
    }

    public func setArguments(_ arguments: [String]) throws {
        try withCStringArray(arguments) { pointers in
            guard wasi_config_set_argv(requiredRaw, pointers.count, pointers.baseAddress) else { // coverage:ignore Swift String UTF-8 is valid
                throw WasmtimeError.wasiConfigurationFailed("WASI argv must contain valid UTF-8")
            }
        }
    }

    public func inheritArguments() {
        wasi_config_inherit_argv(requiredRaw)
    }

    public func setEnvironment(_ environment: [String: String]) throws {
        let entries = environment.sorted { $0.key < $1.key }
        try withCStringArray(entries.map(\.key)) { names in
            try withCStringArray(entries.map(\.value)) { values in
                guard wasi_config_set_env(requiredRaw, names.count, names.baseAddress, values.baseAddress) else { // coverage:ignore Swift String UTF-8 is valid
                    throw WasmtimeError.wasiConfigurationFailed("WASI environment must contain valid UTF-8")
                }
            }
        }
    }

    public func inheritEnvironment() {
        wasi_config_inherit_env(requiredRaw)
    }

    public func inheritStandardInput() {
        wasi_config_inherit_stdin(requiredRaw)
    }

    public func inheritStandardOutput() {
        wasi_config_inherit_stdout(requiredRaw)
    }

    public func inheritStandardError() {
        wasi_config_inherit_stderr(requiredRaw)
    }

    public func setStandardInputFile(_ path: String) throws {
        try path.withCString { cPath in
            guard wasi_config_set_stdin_file(requiredRaw, cPath) else {
                throw WasmtimeError.wasiConfigurationFailed("could not open WASI stdin file: \(path)")
            }
        }
    }

    public func setStandardOutputFile(_ path: String) throws {
        try path.withCString { cPath in
            guard wasi_config_set_stdout_file(requiredRaw, cPath) else {
                throw WasmtimeError.wasiConfigurationFailed("could not open WASI stdout file: \(path)")
            }
        }
    }

    public func setStandardErrorFile(_ path: String) throws {
        try path.withCString { cPath in
            guard wasi_config_set_stderr_file(requiredRaw, cPath) else {
                throw WasmtimeError.wasiConfigurationFailed("could not open WASI stderr file: \(path)")
            }
        }
    }

    func release() -> OpaquePointer {
        let current = requiredRaw
        raw = nil
        return current
    }

    private var requiredRaw: OpaquePointer {
        guard let raw else { // coverage:ignore programmer-error precondition
            preconditionFailure("WasiConfig has already been consumed by Store.setWasi(_:)") // coverage:ignore crash branch
        }
        return raw
    }

    deinit {
        if let raw {
            wasi_config_delete(raw)
        }
    }
}

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

public struct Trap: Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public let code: UInt8?

    public var description: String {
        if let code {
            return "\(message) (trap code \(code))"
        }
        return message
    }

    static func fromOwned(_ raw: OpaquePointer) -> Trap {
        defer { wasm_trap_delete(raw) }
        var message = wasm_message_t()
        wasm_trap_message(raw, &message)
        defer { wasm_byte_vec_delete(&message) }

        var code: wasmtime_trap_code_t = 0
        let hasCode = wasmtime_trap_code(raw, &code)
        return Trap(message: String(wasmByteVec: message), code: hasCode ? code : nil)
    }
}

public enum WasmtimeError: Error, Sendable, Equatable, CustomStringConvertible {
    case api(message: String, exitStatus: Int32?)
    case trap(Trap)
    case allocationFailed(String)
    case missingExport(String)
    case wrongExportKind(name: String, expected: String, actual: String)
    case unsupportedValueKind(Int)
    case wasiConfigurationFailed(String)

    public var description: String {
        switch self {
        case .api(let message, let exitStatus):
            if let exitStatus {
                return "\(message) (WASI exit status \(exitStatus))"
            }
            return message
        case .trap(let trap):
            return trap.description
        case .allocationFailed(let message), .wasiConfigurationFailed(let message):
            return message
        case .missingExport(let name):
            return "missing export: \(name)"
        case .wrongExportKind(let name, let expected, let actual):
            return "export \(name) is \(actual), expected \(expected)"
        case .unsupportedValueKind(let kind):
            return "unsupported Wasmtime value kind: \(kind)"
        }
    }

    static func throwIfNeeded(_ error: OpaquePointer?, trap: OpaquePointer? = nil) throws {
        if let error {
            throw WasmtimeError.fromOwned(error)
        }
        if let trap {
            throw WasmtimeError.trap(Trap.fromOwned(trap))
        }
    }

    static func fromOwned(_ raw: OpaquePointer) -> WasmtimeError {
        defer { wasmtime_error_delete(raw) }
        var message = wasm_message_t()
        wasmtime_error_message(raw, &message)
        defer { wasm_byte_vec_delete(&message) }

        var exitStatus: Int32 = 0
        let hasExitStatus = wasmtime_error_exit_status(raw, &exitStatus)
        return .api(message: String(wasmByteVec: message), exitStatus: hasExitStatus ? exitStatus : nil)
    }
}

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

enum ExternKind: CustomStringConvertible {
    case function
    case global
    case table
    case memory
    case sharedMemory
    case tag
    case unknown(wasmtime_extern_kind_t)

    init(rawValue: wasmtime_extern_kind_t) {
        switch rawValue {
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_FUNC): self = .function
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_GLOBAL): self = .global
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_TABLE): self = .table
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_MEMORY): self = .memory
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_SHAREDMEMORY): self = .sharedMemory
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_TAG): self = .tag
        default: self = .unknown(rawValue)
        }
    }

    var description: String {
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

private func withCStringArray<T>(_ strings: [String], _ body: (UnsafeMutableBufferPointer<UnsafePointer<CChar>?>) throws -> T) rethrows -> T {
    let cStrings = strings.map { strdup($0) }
    defer {
        for pointer in cStrings {
            free(pointer)
        }
    }
    var pointers = cStrings.map { pointer -> UnsafePointer<CChar>? in
        guard let pointer else { return nil } // coverage:ignore defensive libc allocation failure
        return UnsafePointer(pointer)
    }
    return try pointers.withUnsafeMutableBufferPointer { buffer in
        try body(buffer)
    }
}

private extension wasm_byte_vec_t {
    func withUnsafeBytes<T>(_ body: (UnsafeBufferPointer<UInt8>) throws -> T) rethrows -> T {
        let start = data.map { UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self) }
        return try body(UnsafeBufferPointer(start: start, count: size))
    }
}

private extension String {
    init(wasmByteVec bytes: wasm_byte_vec_t) {
        guard bytes.size > 0, let bytesPointer = bytes.data else {
            self = ""
            return
        }
        let data = Data(bytes: UnsafeRawPointer(bytesPointer), count: bytes.size)
        self = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self) // coverage:ignore defensive invalid UTF-8 fallback
    }
}
