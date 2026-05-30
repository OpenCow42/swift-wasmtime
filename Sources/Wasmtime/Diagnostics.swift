import Foundation
@preconcurrency import CWasmtime

#if os(Linux)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Typed Wasmtime instruction trap code.
public enum TrapCode: Sendable, Equatable, Hashable, CustomStringConvertible {
    case stackOverflow
    case memoryOutOfBounds
    case heapMisaligned
    case tableOutOfBounds
    case indirectCallToNull
    case badSignature
    case integerOverflow
    case integerDivisionByZero
    case badConversionToInteger
    case unreachableCodeReached
    case interrupt
    case outOfFuel
    case atomicWaitNonSharedMemory
    case nullReference
    case arrayOutOfBounds
    case allocationTooLarge
    case castFailure
    case cannotEnterComponent
    case noAsyncResult
    case unhandledTag
    case continuationAlreadyConsumed
    case disabledOpcode
    case asyncDeadlock
    case cannotLeaveComponent
    case cannotBlockSyncTask
    case invalidChar
    case debugAssertStringEncodingFinished
    case debugAssertEqualCodeUnits
    case debugAssertPointerAligned
    case debugAssertUpperBitsUnset
    case stringOutOfBounds
    case listOutOfBounds
    case invalidDiscriminant
    case unalignedPointer
    case taskCancelNotCancelled
    case taskCancelOrReturnTwice
    case subtaskCancelAfterTerminal
    case taskReturnInvalid
    case waitableSetDropHasWaiters
    case subtaskDropNotResolved
    case threadNewIndirectInvalidType
    case threadNewIndirectUninitialized
    case backpressureOverflow
    case unsupportedCallbackCode
    case cannotResumeThread
    case concurrentFutureStreamOperation
    case unknown(UInt8)

    public init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .stackOverflow
        case 1: self = .memoryOutOfBounds
        case 2: self = .heapMisaligned
        case 3: self = .tableOutOfBounds
        case 4: self = .indirectCallToNull
        case 5: self = .badSignature
        case 6: self = .integerOverflow
        case 7: self = .integerDivisionByZero
        case 8: self = .badConversionToInteger
        case 9: self = .unreachableCodeReached
        case 10: self = .interrupt
        case 11: self = .outOfFuel
        case 12: self = .atomicWaitNonSharedMemory
        case 13: self = .nullReference
        case 14: self = .arrayOutOfBounds
        case 15: self = .allocationTooLarge
        case 16: self = .castFailure
        case 17: self = .cannotEnterComponent
        case 18: self = .noAsyncResult
        case 19: self = .unhandledTag
        case 20: self = .continuationAlreadyConsumed
        case 21: self = .disabledOpcode
        case 22: self = .asyncDeadlock
        case 23: self = .cannotLeaveComponent
        case 24: self = .cannotBlockSyncTask
        case 25: self = .invalidChar
        case 26: self = .debugAssertStringEncodingFinished
        case 27: self = .debugAssertEqualCodeUnits
        case 28: self = .debugAssertPointerAligned
        case 29: self = .debugAssertUpperBitsUnset
        case 30: self = .stringOutOfBounds
        case 31: self = .listOutOfBounds
        case 32: self = .invalidDiscriminant
        case 33: self = .unalignedPointer
        case 34: self = .taskCancelNotCancelled
        case 35: self = .taskCancelOrReturnTwice
        case 36: self = .subtaskCancelAfterTerminal
        case 37: self = .taskReturnInvalid
        case 38: self = .waitableSetDropHasWaiters
        case 39: self = .subtaskDropNotResolved
        case 40: self = .threadNewIndirectInvalidType
        case 41: self = .threadNewIndirectUninitialized
        case 42: self = .backpressureOverflow
        case 43: self = .unsupportedCallbackCode
        case 44: self = .cannotResumeThread
        case 45: self = .concurrentFutureStreamOperation
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: UInt8 {
        switch self {
        case .stackOverflow: 0
        case .memoryOutOfBounds: 1
        case .heapMisaligned: 2
        case .tableOutOfBounds: 3
        case .indirectCallToNull: 4
        case .badSignature: 5
        case .integerOverflow: 6
        case .integerDivisionByZero: 7
        case .badConversionToInteger: 8
        case .unreachableCodeReached: 9
        case .interrupt: 10
        case .outOfFuel: 11
        case .atomicWaitNonSharedMemory: 12
        case .nullReference: 13
        case .arrayOutOfBounds: 14
        case .allocationTooLarge: 15
        case .castFailure: 16
        case .cannotEnterComponent: 17
        case .noAsyncResult: 18
        case .unhandledTag: 19
        case .continuationAlreadyConsumed: 20
        case .disabledOpcode: 21
        case .asyncDeadlock: 22
        case .cannotLeaveComponent: 23
        case .cannotBlockSyncTask: 24
        case .invalidChar: 25
        case .debugAssertStringEncodingFinished: 26
        case .debugAssertEqualCodeUnits: 27
        case .debugAssertPointerAligned: 28
        case .debugAssertUpperBitsUnset: 29
        case .stringOutOfBounds: 30
        case .listOutOfBounds: 31
        case .invalidDiscriminant: 32
        case .unalignedPointer: 33
        case .taskCancelNotCancelled: 34
        case .taskCancelOrReturnTwice: 35
        case .subtaskCancelAfterTerminal: 36
        case .taskReturnInvalid: 37
        case .waitableSetDropHasWaiters: 38
        case .subtaskDropNotResolved: 39
        case .threadNewIndirectInvalidType: 40
        case .threadNewIndirectUninitialized: 41
        case .backpressureOverflow: 42
        case .unsupportedCallbackCode: 43
        case .cannotResumeThread: 44
        case .concurrentFutureStreamOperation: 45
        case .unknown(let rawValue): rawValue
        }
    }

    public var description: String {
        switch self {
        case .stackOverflow: "stack overflow"
        case .memoryOutOfBounds: "memory out of bounds"
        case .heapMisaligned: "heap misaligned"
        case .tableOutOfBounds: "table out of bounds"
        case .indirectCallToNull: "indirect call to null"
        case .badSignature: "bad signature"
        case .integerOverflow: "integer overflow"
        case .integerDivisionByZero: "integer division by zero"
        case .badConversionToInteger: "bad conversion to integer"
        case .unreachableCodeReached: "unreachable"
        case .interrupt: "interrupt"
        case .outOfFuel: "out of fuel"
        case .atomicWaitNonSharedMemory: "atomic wait on non-shared memory"
        case .nullReference: "null reference"
        case .arrayOutOfBounds: "array out of bounds"
        case .allocationTooLarge: "allocation too large"
        case .castFailure: "cast failure"
        case .cannotEnterComponent: "cannot enter component"
        case .noAsyncResult: "no async result"
        case .unhandledTag: "unhandled tag"
        case .continuationAlreadyConsumed: "continuation already consumed"
        case .disabledOpcode: "disabled opcode"
        case .asyncDeadlock: "async deadlock"
        case .cannotLeaveComponent: "cannot leave component"
        case .cannotBlockSyncTask: "cannot block sync task"
        case .invalidChar: "invalid char"
        case .debugAssertStringEncodingFinished: "debug assert string encoding finished"
        case .debugAssertEqualCodeUnits: "debug assert equal code units"
        case .debugAssertPointerAligned: "debug assert pointer aligned"
        case .debugAssertUpperBitsUnset: "debug assert upper bits unset"
        case .stringOutOfBounds: "string out of bounds"
        case .listOutOfBounds: "list out of bounds"
        case .invalidDiscriminant: "invalid discriminant"
        case .unalignedPointer: "unaligned pointer"
        case .taskCancelNotCancelled: "task.cancel not cancelled"
        case .taskCancelOrReturnTwice: "task.cancel or task.return twice"
        case .subtaskCancelAfterTerminal: "subtask.cancel after terminal"
        case .taskReturnInvalid: "task.return invalid"
        case .waitableSetDropHasWaiters: "waitable-set.drop has waiters"
        case .subtaskDropNotResolved: "subtask.drop not resolved"
        case .threadNewIndirectInvalidType: "thread.new_indirect invalid type"
        case .threadNewIndirectUninitialized: "thread.new_indirect uninitialized"
        case .backpressureOverflow: "backpressure overflow"
        case .unsupportedCallbackCode: "unsupported callback code"
        case .cannotResumeThread: "cannot resume thread"
        case .concurrentFutureStreamOperation: "concurrent future/stream operation"
        case .unknown(let rawValue): "unknown(\(rawValue))"
        }
    }
}

/// A WebAssembly stack frame captured from a trap or Wasmtime error trace.
///
/// This is an immutable snapshot of Wasmtime frame metadata. The underlying
/// `wasm_frame_t` is not exposed because frame handles are tied to Wasmtime
/// ownership and store-bound instance lifetimes, while diagnostics should be
/// safe to inspect after the original trap/error has been released.
public struct WasmFrame: Sendable, Equatable, CustomStringConvertible {
    public let functionIndex: UInt32
    public let functionOffset: Int
    public let moduleOffset: Int
    public let functionName: String?
    public let moduleName: String?

    public init(
        functionIndex: UInt32,
        functionOffset: Int,
        moduleOffset: Int,
        functionName: String? = nil,
        moduleName: String? = nil
    ) {
        self.functionIndex = functionIndex
        self.functionOffset = functionOffset
        self.moduleOffset = moduleOffset
        self.functionName = functionName
        self.moduleName = moduleName
    }

    public var description: String {
        var parts = ["func #\(functionIndex)"]
        if let functionName, !functionName.isEmpty {
            parts.append("(\(functionName))")
        }
        if let moduleName, !moduleName.isEmpty {
            parts.append("in \(moduleName)")
        }
        parts.append("func offset \(functionOffset)")
        parts.append("module offset \(moduleOffset)")
        return parts.joined(separator: " ")
    }

    fileprivate init(raw: OpaquePointer) {
        functionIndex = wasm_frame_func_index(raw)
        functionOffset = Int(wasm_frame_func_offset(raw))
        moduleOffset = Int(wasm_frame_module_offset(raw))
        functionName = wasmtime_frame_func_name(raw).map { String(wasmByteVec: $0.pointee) }
        moduleName = wasmtime_frame_module_name(raw).map { String(wasmByteVec: $0.pointee) }
    }
}

/// WebAssembly trace captured from a trap or Wasmtime error.
///
/// Traces store Swift value snapshots rather than borrowed Wasmtime frame
/// handles, so they can be retained or passed across concurrency boundaries.
public struct WasmTrace: Sendable, Equatable, CustomStringConvertible {
    public let frames: [WasmFrame]

    public init(frames: [WasmFrame] = []) {
        self.frames = frames
    }

    public var isEmpty: Bool {
        frames.isEmpty
    }

    public var description: String {
        frames.map(\.description).joined(separator: "\n")
    }

    fileprivate init(raw vector: wasm_frame_vec_t) {
        guard vector.size > 0 else {
            frames = []
            return
        }
        guard let data = vector.data else {
            frames = [] // coverage:ignore defensive C invariant
            return // coverage:ignore defensive C invariant
        }
        frames = (0..<Int(vector.size)).compactMap { index in
            data[index].map { WasmFrame(raw: $0) }
        }
    }
}

/// WebAssembly trap surfaced from guest execution.
public struct Trap: Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public let code: TrapCode?
    public let origin: WasmFrame?
    public let trace: WasmTrace

    public init(message: String, code: TrapCode? = nil, origin: WasmFrame? = nil, trace: WasmTrace = WasmTrace()) {
        self.message = message
        self.code = code
        self.origin = origin
        self.trace = trace
    }

    public init(message: String, rawCode: UInt8?, origin: WasmFrame? = nil, trace: WasmTrace = WasmTrace()) {
        self.init(message: message, code: rawCode.map(TrapCode.init(rawValue:)), origin: origin, trace: trace)
    }

    public var rawCode: UInt8? {
        code?.rawValue
    }

    public static func host(message: String) -> Trap {
        Trap(message: message)
    }

    public static func instruction(code: TrapCode, message: String? = nil) -> Trap {
        Trap(message: message ?? code.description, code: code)
    }

    public var description: String {
        let base: String
        if let code {
            base = "\(message) (trap code \(code))"
        } else {
            base = message
        }
        guard !trace.isEmpty else {
            return base
        }
        return "\(base)\n\(trace.description)"
    }

    static func fromOwned(_ raw: OpaquePointer) -> Trap {
        defer { wasm_trap_delete(raw) }
        var message = wasm_message_t()
        wasm_trap_message(raw, &message)
        defer { wasm_byte_vec_delete(&message) }

        var code: wasmtime_trap_code_t = 0
        let hasCode = wasmtime_trap_code(raw, &code)

        let origin = wasm_trap_origin(raw).map { frame in
            defer { wasm_frame_delete(frame) }
            return WasmFrame(raw: frame)
        }

        var traceVector = wasm_frame_vec_t()
        wasm_trap_trace(raw, &traceVector)
        defer { wasm_frame_vec_delete(&traceVector) }
        let trace = WasmTrace(raw: traceVector)

        return Trap(
            message: String(wasmByteVec: message),
            code: hasCode ? TrapCode(rawValue: code) : nil,
            origin: origin,
            trace: trace
        )
    }
}

/// Errors surfaced by the Swift Wasmtime wrapper.
///
/// This enum may gain cases as more Wasmtime API surface is wrapped.
public enum WasmtimeError: Error, Sendable, Equatable, CustomStringConvertible {
    case api(message: String, exitStatus: Int32?)
    case apiWithTrace(message: String, exitStatus: Int32?, trace: WasmTrace)
    case trap(Trap)
    case allocationFailed(String)
    case missingExport(String)
    case missingRuntimeInstance(RuntimeInstanceID)
    case missingRuntimeComponentInstance(RuntimeComponentInstanceID)
    case wrongExportKind(name: String, expected: String, actual: String)
    case unsupportedValueKind(Int)
    case wasiConfigurationFailed(String)
    case memoryAccessOutOfBounds(offset: Int, length: Int, memorySize: Int)
    case callerExpired

    public var description: String {
        switch self {
        case .api(let message, let exitStatus):
            if let exitStatus {
                return "\(message) (WASI exit status \(exitStatus))"
            }
            return message
        case .apiWithTrace(let message, let exitStatus, let trace):
            let base: String
            if let exitStatus {
                base = "\(message) (WASI exit status \(exitStatus))"
            } else {
                base = message
            }
            guard !trace.isEmpty else {
                return base
            }
            return "\(base)\n\(trace.description)"
        case .trap(let trap):
            return trap.description
        case .allocationFailed(let message), .wasiConfigurationFailed(let message):
            return message
        case .missingExport(let name):
            return "missing export: \(name)"
        case .missingRuntimeInstance(let id):
            return "missing runtime instance: \(id.rawValue)"
        case .missingRuntimeComponentInstance(let id):
            return "missing runtime component instance: \(id.rawValue)"
        case .wrongExportKind(let name, let expected, let actual):
            return "export \(name) is \(actual), expected \(expected)"
        case .unsupportedValueKind(let kind):
            return "unsupported Wasmtime value kind: \(kind)"
        case .memoryAccessOutOfBounds(let offset, let length, let memorySize):
            return "memory access out of bounds: offset \(offset), length \(length), memory size \(memorySize)"
        case .callerExpired:
            return "caller is only valid during host function execution"
        }
    }

    public var trace: WasmTrace {
        switch self {
        case .trap(let trap):
            return trap.trace
        case .apiWithTrace(_, _, let trace):
            return trace
        default:
            return WasmTrace()
        }
    }

    public static func hostTrap(message: String) -> WasmtimeError {
        .trap(.host(message: message))
    }

    public static func hostError(message: String, exitStatus: Int32? = nil) -> WasmtimeError {
        .api(message: message, exitStatus: exitStatus)
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
        var traceVector = wasm_frame_vec_t()
        wasmtime_error_wasm_trace(raw, &traceVector)
        defer { wasm_frame_vec_delete(&traceVector) }
        let trace = WasmTrace(raw: traceVector)
        let swiftMessage = String(wasmByteVec: message)
        guard !trace.isEmpty else {
            return .api(message: swiftMessage, exitStatus: hasExitStatus ? exitStatus : nil)
        }
        return .apiWithTrace(message: swiftMessage, exitStatus: hasExitStatus ? exitStatus : nil, trace: trace)
    }
}
