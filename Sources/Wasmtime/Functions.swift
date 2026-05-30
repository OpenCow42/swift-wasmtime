import Foundation
@preconcurrency import CWasmtime

#if os(Linux)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Store-bound WebAssembly or host function.
///
/// `Func` is not `Sendable`. Call it only on the serialized execution path that
/// owns its `Store`, or expose behavior through `WasmtimeRuntime`.
public final class Func {
    let store: Store
    let raw: wasmtime_func_t

    /// Creates a store-bound host function.
    ///
    /// The callback receives a temporary `Caller` and typed scalar arguments.
    /// It must return exactly the result values declared by `type`.
    public init(
        store: Store,
        type: FunctionType,
        _ body: @escaping HostFunction
    ) throws {
        let rawType = try type.makeRaw()
        defer { wasm_functype_delete(rawType) }
        let box = HostFunctionBox(type: type, body: body)
        let data = Unmanaged.passRetained(box).toOpaque()
        var function = wasmtime_func_t()
        wasmtime_func_new(
            store.context,
            rawType,
            hostFunctionCallback,
            data,
            hostFunctionFinalizer,
            &function
        )
        self.store = store
        self.raw = function
    }

    public convenience init(
        store: Store,
        parameters: [ValueKind] = [],
        results: [ValueKind] = [],
        _ body: @escaping HostFunction
    ) throws {
        try self.init(store: store, type: FunctionType(parameters: parameters, results: results), body)
    }

    init(store: Store, raw: wasmtime_func_t) {
        self.store = store
        self.raw = raw
    }

    /// Returns the scalar parameter and result kinds accepted by this function.
    ///
    /// Reference-typed signatures throw `WasmtimeError.unsupportedValueKind`
    /// until the package grows broader reference value modeling.
    public func type() throws -> FunctionType {
        var function = raw
        guard let type = wasmtime_func_type(store.context, &function) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasmtime_func_type returned nil") // coverage:ignore defensive C invariant
        }
        defer { wasm_functype_delete(type) }
        return try FunctionType(raw: type)
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

/// Store-bound exported component function.
///
/// `ComponentFunction` is not `Sendable`. Use it only on the serialized
/// execution path that owns its `Store`, or call through `WasmtimeRuntime`.
public final class ComponentFunction {
    private let store: Store
    let raw: wasmtime_component_func_t

    init(store: Store, raw: wasmtime_component_func_t) {
        self.store = store
        self.raw = raw
    }

    public func call() throws {
        var function = raw
        try WasmtimeError.throwIfNeeded(
            wasmtime_component_func_call(&function, store.context, nil, 0, nil, 0)
        )
    }
}

/// Checked host function callback for low-level `Func` and `Linker` APIs.
///
/// The callback is `@Sendable`; capture only thread-safe state or serialize
/// access yourself. The `Caller` is valid only for the current invocation.
public typealias HostFunction = @Sendable (_ caller: Caller, _ arguments: [Value]) throws -> [Value]
/// Checked host function callback for actor-managed runtime APIs.
public typealias SendableHostFunction = @Sendable (_ arguments: [Value]) throws -> [Value]

/// Sendable host-function definition for `WasmtimeRuntime`.
public struct RuntimeHostFunction: Sendable {
    public var module: String
    public var name: String
    public var type: FunctionType
    public var body: SendableHostFunction

    public init(
        module: String,
        name: String,
        type: FunctionType,
        body: @escaping SendableHostFunction
    ) {
        self.module = module
        self.name = name
        self.type = type
        self.body = body
    }

    public init(
        module: String,
        name: String,
        parameters: [ValueKind] = [],
        results: [ValueKind] = [],
        body: @escaping SendableHostFunction
    ) {
        self.init(module: module, name: name, type: FunctionType(parameters: parameters, results: results), body: body)
    }
}

final class HostFunctionBox {
    let type: FunctionType
    let body: HostFunction

    init(type: FunctionType, body: @escaping HostFunction) {
        self.type = type
        self.body = body
    }
}

let hostFunctionCallback: wasmtime_func_callback_t = { data, caller, args, nargs, results, nresults in
    guard let data else {
        return makeHostTrap("missing host function data") // coverage:ignore defensive C callback invariant
    }

    let box = Unmanaged<HostFunctionBox>.fromOpaque(data).takeUnretainedValue()
    do {
        let arguments = try convertHostArguments(args, count: nargs)
        let caller = Caller(raw: caller)
        defer { caller.invalidate() }
        let values = try box.body(caller, arguments)
        guard values.count == nresults else {
            return makeHostTrap("host function returned \(values.count) results, expected \(nresults)")
        }
        for (index, value) in values.enumerated() {
            let expectedKind = box.type.results[index]
            guard value.kind == expectedKind else {
                return makeHostTrap("host function returned \(value.kind) at result \(index), expected \(expectedKind)")
            }
            results![index] = value.rawValue
        }
        return nil
    } catch {
        return makeHostTrap(String(describing: error))
    }
}

let hostFunctionFinalizer: (@convention(c) (UnsafeMutableRawPointer?) -> Void) = { data in
    if let data {
        Unmanaged<HostFunctionBox>.fromOpaque(data).release()
    }
}

private func convertHostArguments(_ args: UnsafePointer<wasmtime_val_t>?, count: Int) throws -> [Value] {
    guard count > 0 else {
        return []
    }
    guard let args else { // coverage:ignore defensive C invariant
        return []
    }
    return try (0..<count).map { index in
        try Value(rawValue: args[index])
    }
}

private func makeHostTrap(_ message: String) -> OpaquePointer? {
    message.withCString { cMessage in
        wasmtime_trap_new(cMessage, strlen(cMessage))
    }
}
