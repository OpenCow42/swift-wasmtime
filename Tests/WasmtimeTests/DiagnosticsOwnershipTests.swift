import Foundation
import Testing
@preconcurrency import CWasmtime
@testable import Wasmtime

@Test func repeatedCreateAndDropLoopsExerciseOwnership() throws {
    for index in 0..<25 {
        let engine = try Engine()
        let store = try Store(engine: engine)
        let module = try Module(
            engine: engine,
            wat: "(module (func (export \"id\") (param i32) (result i32) local.get 0))"
        )
        let function = try Instance(store: store, module: module).exportedFunction(named: "id")
        #expect(try function.call([.i32(Int32(index))]) == [.i32(Int32(index))])
    }
}

@Test func errorDescriptionsAreUseful() {
    #expect(Value.i32(1).description == "i32(1)")
    #expect(Value.i64(2).description == "i64(2)")
    #expect(Value.f32(3).description == "f32(3.0)")
    #expect(Value.f64(4).description == "f64(4.0)")
    #expect(Trap(message: "boom", code: .unreachableCodeReached).description == "boom (trap code unreachable)")
    #expect(Trap(message: "boom", rawCode: 9).code == .unreachableCodeReached)
    #expect(Trap(message: "boom", rawCode: 9).rawCode == 9)
    #expect(Trap(message: "boom", code: nil).description == "boom")
    #expect(WasmtimeError.trap(Trap(message: "boom", code: nil)).description == "boom")
    #expect(Trap.host(message: "host boom") == Trap(message: "host boom"))
    #expect(Trap.instruction(code: .memoryOutOfBounds).description == "memory out of bounds (trap code memory out of bounds)")
    #expect(WasmtimeError.hostTrap(message: "host boom").description == "host boom")
    #expect(WasmtimeError.hostError(message: "host failed").description == "host failed")
    #expect(WasmtimeError.hostError(message: "guest exited", exitStatus: 7).description == "guest exited (WASI exit status 7)")
    #expect(TrapCode(rawValue: 255) == .unknown(255))
    #expect(TrapCode.unknown(255).rawValue == 255)
    #expect(TrapCode.unknown(255).description == "unknown(255)")
    #expect(TrapCode.integerDivisionByZero.rawValue == 7)
    #expect(TrapCode.integerDivisionByZero.description == "integer division by zero")
    let frame = WasmFrame(
        functionIndex: 3,
        functionOffset: 7,
        moduleOffset: 11,
        functionName: "run",
        moduleName: "fixture"
    )
    let trace = WasmTrace(frames: [frame])
    #expect(frame.description == "func #3 (run) in fixture func offset 7 module offset 11")
    #expect(trace.description == frame.description)
    #expect(!trace.isEmpty)
    #expect(Trap(message: "boom", code: nil, trace: trace).description.contains(frame.description))
    #expect(WasmtimeError.apiWithTrace(message: "bad", exitStatus: 2, trace: trace).description.contains(frame.description))
    #expect(WasmtimeError.apiWithTrace(message: "bad", exitStatus: nil, trace: WasmTrace()).description == "bad")
    #expect(WasmtimeError.trap(Trap(message: "boom", code: nil, trace: trace)).trace == trace)
    #expect(WasmtimeError.apiWithTrace(message: "bad", exitStatus: nil, trace: trace).trace == trace)
    #expect(WasmtimeError.missingExport("gone").trace.isEmpty)
    #expect(WasmtimeError.allocationFailed("nope").description == "nope")
    #expect(WasmtimeError.missingExport("gone").description == "missing export: gone")
    #expect(RuntimeInstanceID(rawValue: 7).description == "runtime instance 7")
    #expect(WasmtimeError.missingRuntimeInstance(RuntimeInstanceID(rawValue: 7)).description == "missing runtime instance: 7")
    #expect(RuntimeComponentInstanceID(rawValue: 8).description == "runtime component instance 8")
    #expect(WasmtimeError.missingRuntimeComponentInstance(RuntimeComponentInstanceID(rawValue: 8)).description == "missing runtime component instance: 8")
    #expect(WasmtimeError.api(message: "bad", exitStatus: 2).description == "bad (WASI exit status 2)")
    #expect(WasmtimeError.api(message: "bad", exitStatus: nil).description == "bad")
    #expect(WasmtimeError.unsupportedValueKind(99).description == "unsupported Wasmtime value kind: 99")
    #expect(WasmtimeError.wrongExportKind(name: "x", expected: "func", actual: "global").description == "export x is global, expected func")
    #expect(WasmtimeError.callerExpired.description == "caller is only valid during host function execution")
}

@Test func internalConversionsHandleUnsupportedValuesAndOwnedErrors() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)

    var rawValue = wasmtime_val_t()
    rawValue.kind = 99
    try expectSpecificError(.unsupportedValueKind(99)) {
        _ = try Value(rawValue: rawValue)
    }

    let unknownTableElementKind = TableElementKind(rawValue: 77)
    #expect(unknownTableElementKind == .unknown(77))
    #expect(unknownTableElementKind.wasmRawValue == 77)
    #expect(unknownTableElementKind.description == "unknown(77)")
    try expectSpecificError(.unsupportedValueKind(77)) {
        _ = try TableElement.null(for: unknownTableElementKind)
    }
    try expectSpecificError(.unsupportedValueKind(77)) {
        _ = try TableType(element: unknownTableElementKind, minimumElements: 0)
    }

    var rawUnsupportedTableElement = wasmtime_val_t()
    rawUnsupportedTableElement.kind = wasmtime_valkind_t(WASMTIME_I32)
    try expectSpecificError(.unsupportedValueKind(Int(WASMTIME_I32))) {
        _ = try TableElement(store: store, rawValue: rawUnsupportedTableElement)
    }

    var rawNonNullExternReference = wasmtime_val_t()
    rawNonNullExternReference.kind = wasmtime_valkind_t(WASMTIME_EXTERNREF)
    rawNonNullExternReference.of.externref.store_id = 1
    try expectSpecificError(.unsupportedValueKind(Int(WASMTIME_EXTERNREF))) {
        _ = try TableElement(store: store, rawValue: rawNonNullExternReference)
    }

    var rawUnsupportedExtern = wasmtime_extern_t()
    rawUnsupportedExtern.kind = wasmtime_extern_kind_t(WASMTIME_EXTERN_TAG)
    let unsupportedExtern = Extern(store: store, raw: rawUnsupportedExtern)
    #expect(unsupportedExtern.kind == .tag)

    let manualError = try #require(wasmtime_error_new("manual error"))
    #expect(WasmtimeError.fromOwned(manualError).description == "manual error")

    let emptyError = try #require(wasmtime_error_new(""))
    #expect(WasmtimeError.fromOwned(emptyError).description == "")

    let message = "host trap"
    let hostTrap = try message.withCString { cMessage in
        try #require(wasmtime_trap_new(cMessage, strlen(cMessage)))
    }
    let swiftHostTrap = Trap.fromOwned(hostTrap)
    #expect(swiftHostTrap.description.contains("host trap"))
    #expect(swiftHostTrap.origin == nil)
    #expect(swiftHostTrap.trace.isEmpty)

    let codeTrap = try #require(wasmtime_trap_new_code(wasmtime_trap_code_t(WASMTIME_TRAP_CODE_MEMORY_OUT_OF_BOUNDS.rawValue)))
    let swiftCodeTrap = Trap.fromOwned(codeTrap)
    #expect(swiftCodeTrap.code == .memoryOutOfBounds)
    #expect(swiftCodeTrap.rawCode == 1)
    #expect(swiftCodeTrap.description.contains("memory out of bounds"))
}
