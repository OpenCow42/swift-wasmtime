import Foundation
import Testing
@preconcurrency import CWasmtime
@testable import Wasmtime

@Test func callsScalarValueFunctions() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (func (export "i64_id") (param i64) (result i64) local.get 0)
          (func (export "f32_id") (param f32) (result f32) local.get 0)
          (func (export "f64_id") (param f64) (result f64) local.get 0)
          (func (export "nothing")))
        """
    )
    let instance = try Instance(store: store, module: module)

    #expect(try instance.exportedFunction(named: "i64_id").call([.i64(9_000_000_000)]) == [.i64(9_000_000_000)])
    #expect(try instance.exportedFunction(named: "f32_id").call([.f32(1.5)]) == [.f32(1.5)])
    #expect(try instance.exportedFunction(named: "f64_id").call([.f64(2.5)]) == [.f64(2.5)])
    #expect(try instance.exportedFunction(named: "nothing").call() == [])
}

@Test func functionsExposeScalarTypes() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (func (export "mix") (param i32 i64 f32 f64) (result i64 f32)
            local.get 1
            local.get 2))
        """
    )
    let instance = try Instance(store: store, module: module)
    let mix = try instance.exportedFunction(named: "mix")

    #expect(try mix.type() == FunctionType(parameters: [.i32, .i64, .f32, .f64], results: [.i64, .f32]))

    switch try instance.export(named: "mix") {
    case .function(let function):
        #expect(try function.type() == FunctionType(parameters: [.i32, .i64, .f32, .f64], results: [.i64, .f32]))
    default:
        Issue.record("expected function extern")
    }
}

@Test func hostFunctionsExposeDeclaredTypes() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let type = FunctionType(parameters: [.i32, .i64], results: [.i64])
    let function = try Func(store: store, type: type) { _, arguments in
        guard case .i64(let value) = arguments[1] else {
            return [.i64(0)]
        }
        return [.i64(value)]
    }

    #expect(try function.type() == type)
    #expect(try function.call([.i32(1), .i64(2)]) == [.i64(2)])
}

@Test func functionTypeRejectsUnsupportedReferenceKinds() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (func (export "takes_ref") (param funcref)))
        """
    )
    let function = try Instance(store: store, module: module).exportedFunction(named: "takes_ref")

    do {
        _ = try function.type()
        Issue.record("expected unsupported value kind")
    } catch let error as WasmtimeError {
        #expect(error == .unsupportedValueKind(Int(wasm_valkind_t(WASM_FUNCREF.rawValue))))
    }
}

@Test func exportedFunctionReportsMissingAndWrongKindExports() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (global (export "answer") i32 (i32.const 42)))
        """
    )
    let instance = try Instance(store: store, module: module)

    try expectSpecificError(.missingExport("missing")) {
        _ = try instance.exportedFunction(named: "missing")
    }

    do {
        _ = try instance.exportedFunction(named: "answer")
        Issue.record("expected wrong export kind error")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("expected func"))
    }
}

@Test func wrongExportKindDescriptionsCoverSupportedExternKinds() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (global (export "global") i32 (i32.const 42))
          (memory (export "memory") 1)
          (table (export "table") 1 funcref))
        """
    )
    let instance = try Instance(store: store, module: module)

    for (name, kind) in [("global", "global"), ("memory", "memory"), ("table", "table")] {
        do {
            _ = try instance.exportedFunction(named: name)
            Issue.record("expected wrong export kind error")
        } catch let error as WasmtimeError {
            #expect(error.description.contains("is \(kind)"))
        }
    }

    #expect(ExternKind(rawValue: wasmtime_extern_kind_t(WASMTIME_EXTERN_FUNC)).description == "func")
    #expect(ExternKind(rawValue: wasmtime_extern_kind_t(WASMTIME_EXTERN_GLOBAL)).description == "global")
    #expect(ExternKind(rawValue: wasmtime_extern_kind_t(WASMTIME_EXTERN_TABLE)).description == "table")
    #expect(ExternKind(rawValue: wasmtime_extern_kind_t(WASMTIME_EXTERN_MEMORY)).description == "memory")
    #expect(ExternKind(rawValue: wasmtime_extern_kind_t(WASMTIME_EXTERN_SHAREDMEMORY)).description == "sharedMemory")
    #expect(ExternKind(rawValue: wasmtime_extern_kind_t(WASMTIME_EXTERN_TAG)).description == "tag")
    #expect(ExternKind(rawValue: 255).description == "unknown(255)")
}

@Test func wrongFunctionArgumentsBecomeApiErrors() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (func (export "add") (param i32 i32) (result i32)
            local.get 0
            local.get 1
            i32.add))
        """
    )
    let add = try Instance(store: store, module: module).exportedFunction(named: "add")

    try expectWasmtimeError {
        _ = try add.call([.i32(1)])
    }

    try expectWasmtimeError {
        _ = try add.call([.i64(1), .i32(2)])
    }
}

@Test func wasmTrapBecomesTrapError() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (func (export "boom") (result i32)
            unreachable))
        """
    )
    let boom = try Instance(store: store, module: module).exportedFunction(named: "boom")

    do {
        _ = try boom.call()
        Issue.record("expected trap")
    } catch let error as WasmtimeError {
        guard case .trap(let trap) = error else {
            Issue.record("expected trap")
            return
        }
        #expect(trap.description.contains("unreachable"))
        #expect(trap.code == .unreachableCodeReached)
        #expect(trap.rawCode == 9)
        #expect(!trap.trace.isEmpty)
        #expect(error.trace == trap.trace)
        let frame = try #require(trap.trace.frames.first)
        #expect(trap.origin == frame)
        #expect(frame.functionIndex == 0)
        #expect(frame.functionOffset >= 0)
        #expect(frame.moduleOffset >= 0)
        #expect(trap.description.contains("func #0"))
    }
}

@Test func linkerInstantiatesModulesAndRegistersWasi() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(engine: engine, wat: "(module (func (export \"run\")))")
    let linker = try Linker(engine: engine)

    linker.allowsShadowing = true
    let instance = try linker.instantiate(store: store, module: module)
    #expect(try instance.exportedFunction(named: "run").call() == [])

    let wasi = try WasiConfig()
    try wasi.setArguments(["guest.wasm", "--flag"])
    try wasi.setEnvironment(["A": "B", "C": "D"])
    wasi.inheritArguments()
    wasi.inheritEnvironment()
    wasi.inheritStandardInput()
    wasi.inheritStandardOutput()
    wasi.inheritStandardError()
    try store.setWasi(wasi)
    try linker.defineWasi()
}

@Test func linkerPreInstantiatesModulesAndReusesThemAcrossStores() throws {
    let engine = try Engine()
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (import "host" "answer" (func $answer (result i32)))
          (func (export "run") (result i32)
            call $answer))
        """
    )
    let linker = try Linker(engine: engine)
    try linker.defineFunction(module: "host", name: "answer", results: [.i32]) { _, _ in
        [.i32(42)]
    }

    let pre = try linker.instantiatePre(module: module)
    let firstStore = try Store(engine: engine)
    let firstInstance = try pre.instantiate(store: firstStore)
    #expect(try firstInstance.exportedFunction(named: "run").call() == [.i32(42)])

    let secondStore = try Store(engine: engine)
    let secondInstance = try pre.instantiate(store: secondStore)
    #expect(try secondInstance.exportedFunction(named: "run").call() == [.i32(42)])

    let clonedModule = try pre.module()
    let clonedPre = try linker.instantiatePre(module: clonedModule)
    let clonedInstance = try clonedPre.instantiate(store: Store(engine: engine))
    #expect(try clonedInstance.exportedFunction(named: "run").call() == [.i32(42)])
}

@Test func linkerPreInstantiationReportsLinkErrorsAndStartTraps() throws {
    let engine = try Engine()
    let missingImportModule = try Module(
        engine: engine,
        wat: """
        (module
          (import "host" "missing" (func $missing))
          (func (export "run")
            call $missing))
        """
    )
    let linker = try Linker(engine: engine)

    try expectWasmtimeError {
        _ = try linker.instantiatePre(module: missingImportModule)
    }

    let trapModule = try Module(
        engine: engine,
        wat: """
        (module
          (func $start
            unreachable)
          (start $start))
        """
    )
    let trapPre = try linker.instantiatePre(module: trapModule)
    do {
        _ = try trapPre.instantiate(store: Store(engine: engine))
        Issue.record("expected start trap")
    } catch WasmtimeError.trap(let trap) {
        #expect(trap.description.contains("unreachable"))
    }
}

@Test func linkerDefinesUnknownImportsAsTrapsAndDefaultValues() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let trapModule = try Module(
        engine: engine,
        wat: """
        (module
          (import "env" "missing" (func $missing))
          (func (export "run")
            call $missing))
        """
    )
    let trapLinker = try Linker(engine: engine)
    try trapLinker.defineUnknownImportsAsTraps(module: trapModule)
    let trapInstance = try trapLinker.instantiate(store: store, module: trapModule)

    do {
        _ = try trapInstance.exportedFunction(named: "run").call()
        Issue.record("expected trap")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("unknown import"))
    }

    let defaultModule = try Module(
        engine: engine,
        wat: """
        (module
          (import "env" "answer" (func $answer (result i32)))
          (func (export "run") (result i32)
            call $answer))
        """
    )
    let defaultLinker = try Linker(engine: engine)
    try defaultLinker.defineUnknownImportsAsDefaultValues(store: store, module: defaultModule)
    let defaultInstance = try defaultLinker.instantiate(store: store, module: defaultModule)

    #expect(try defaultInstance.exportedFunction(named: "run").call() == [.i32(0)])
}

@Test func linkerDefinesInstancesAndModulesByName() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let providerModule = try Module(
        engine: engine,
        wat: """
        (module
          (func (export "answer") (result i32)
            i32.const 42))
        """
    )
    let consumerModule = try Module(
        engine: engine,
        wat: """
        (module
          (import "provider" "answer" (func $answer (result i32)))
          (func (export "run") (result i32)
            call $answer))
        """
    )

    let providerInstance = try Instance(store: store, module: providerModule)
    let instanceLinker = try Linker(engine: engine)
    try instanceLinker.defineInstance(store: store, name: "provider", instance: providerInstance)
    let instanceConsumer = try instanceLinker.instantiate(store: store, module: consumerModule)
    #expect(try instanceConsumer.exportedFunction(named: "run").call() == [.i32(42)])

    let moduleLinker = try Linker(engine: engine)
    try moduleLinker.defineModule(store: store, name: "provider", module: providerModule)
    let moduleConsumer = try moduleLinker.instantiate(store: store, module: consumerModule)
    #expect(try moduleConsumer.exportedFunction(named: "run").call() == [.i32(42)])
}

@Test func hostFunctionsCanBeCalledDirectlyAndLinkedAsStoreBoundExterns() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let add = try Func(store: store, parameters: [.i32, .i32], results: [.i32]) { _, arguments in
        guard case .i32(let left) = arguments[0], case .i32(let right) = arguments[1] else {
            throw WasmtimeError.api(message: "unexpected arguments", exitStatus: nil)
        }
        return [.i32(left + right)]
    }

    #expect(ValueKind.i32.description == "i32")
    #expect(ValueKind.f32.description == "f32")
    #expect(ValueKind.f64.description == "f64")
    #expect(Value.i64(5).kind == .i64)
    #expect(try add.call([.i32(20), .i32(22)]) == [.i32(42)])
    #expect(try add.type() == FunctionType(parameters: [.i32, .i32], results: [.i32]))

    let module = try Module(
        engine: engine,
        wat: """
        (module
          (import "host" "add" (func $add (param i32 i32) (result i32)))
          (func (export "run") (result i32)
            i32.const 7
            i32.const 8
            call $add))
        """
    )
    let linker = try Linker(engine: engine)
    try linker.define(module: "host", name: "add", function: add)
    switch try #require(linker.get(store: store, module: "host", name: "add")) {
    case .function(let linkedAdd):
        #expect(try linkedAdd.type() == FunctionType(parameters: [.i32, .i32], results: [.i32]))
    default:
        Issue.record("expected linked function extern")
    }
    let instance = try linker.instantiate(store: store, module: module)

    #expect(try instance.exportedFunction(named: "run").call() == [.i32(15)])
    #expect(try instance.exportedFunction(named: "run").type() == FunctionType(results: [.i32]))
}

@Test func linkerDefinesStoreIndependentHostFunctions() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (import "math" "sum" (func $sum (param i32 i64 f32 f64) (result i32 i64 f32 f64)))
          (func (export "run") (result i32 i64 f32 f64)
            i32.const 40
            i64.const 39
            f32.const 1.5
            f64.const 2.5
            call $sum))
        """
    )
    let linker = try Linker(engine: engine)
    try linker.defineFunction(
        module: "math",
        name: "sum",
        type: FunctionType(parameters: [.i32, .i64, .f32, .f64], results: [.i32, .i64, .f32, .f64])
    ) { _, arguments in
        guard
            case .i32(let int32) = arguments[0],
            case .i64(let int64) = arguments[1],
            case .f32(let float32) = arguments[2],
            case .f64(let float64) = arguments[3]
        else {
            throw WasmtimeError.api(message: "unexpected arguments", exitStatus: nil)
        }
        return [.i32(int32 + 2), .i64(int64 + 3), .f32(float32 + 4), .f64(float64 + 5)]
    }
    try expectWasmtimeError {
        try linker.defineFunction(module: "math", name: "sum", type: FunctionType()) { _, _ in [] }
    }
    let instance = try linker.instantiate(store: store, module: module)

    #expect(try instance.exportedFunction(named: "run").call() == [.i32(42), .i64(42), .f32(5.5), .f64(7.5)])
    #expect(
        try instance.exportedFunction(named: "run").type() ==
            FunctionType(results: [.i32, .i64, .f32, .f64])
    )
}

@Test func hostFunctionsTrapWhenThrowingOrReturningInvalidResults() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let throwingModule = try Module(
        engine: engine,
        wat: """
        (module
          (import "host" "fail" (func $fail))
          (func (export "run")
            call $fail))
        """
    )
    let throwingLinker = try Linker(engine: engine)
    try throwingLinker.defineFunction(module: "host", name: "fail", type: FunctionType()) { _, _ in
        throw WasmtimeError.api(message: "host failed", exitStatus: nil)
    }
    let throwingInstance = try throwingLinker.instantiate(store: store, module: throwingModule)
    do {
        _ = try throwingInstance.exportedFunction(named: "run").call()
        Issue.record("expected host trap")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("host failed"))
    }

    let wrongCountModule = try Module(
        engine: engine,
        wat: """
        (module
          (import "host" "wrong_count" (func $wrong_count (result i32)))
          (func (export "run") (result i32)
            call $wrong_count))
        """
    )
    let wrongCountLinker = try Linker(engine: engine)
    try wrongCountLinker.defineFunction(module: "host", name: "wrong_count", type: FunctionType(results: [.i32])) { _, _ in
        []
    }
    let wrongCountInstance = try wrongCountLinker.instantiate(store: store, module: wrongCountModule)
    do {
        _ = try wrongCountInstance.exportedFunction(named: "run").call()
        Issue.record("expected result count trap")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("expected 1"))
    }

    let wrongKindLinker = try Linker(engine: engine)
    try wrongKindLinker.defineFunction(module: "host", name: "wrong_count", type: FunctionType(results: [.i32])) { _, _ in
        [.i64(1)]
    }
    let wrongKindInstance = try wrongKindLinker.instantiate(store: store, module: wrongCountModule)
    do {
        _ = try wrongKindInstance.exportedFunction(named: "run").call()
        Issue.record("expected result kind trap")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("expected i32"))
    }
}

@Test func hostFunctionCallerReadsAndWritesExportedMemory() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (import "host" "uppercase" (func $uppercase (param i32 i32) (result i32)))
          (memory (export "memory") 1)
          (data (i32.const 0) "hello")
          (func (export "run") (result i32)
            i32.const 0
            i32.const 5
            call $uppercase
            drop
            i32.const 0
            i32.load8_u
            i32.const 72
            i32.eq))
        """
    )
    let linker = try Linker(engine: engine)
    try linker.defineFunction(module: "host", name: "uppercase", parameters: [.i32, .i32], results: [.i32]) { caller, arguments in
        #expect(try caller.exportKind(named: "memory") == .memory)
        #expect(try caller.exportKind(named: "missing") == nil)
        #expect(try caller.readMemory(named: "missing", offset: 0, length: 1) == nil)
        #expect(try caller.writeMemory(named: "missing", offset: 0, bytes: [1]) == false)

        guard case .i32(let offset) = arguments[0], case .i32(let length) = arguments[1] else {
            throw WasmtimeError.api(message: "unexpected arguments", exitStatus: nil)
        }
        let input = try #require(try caller.readMemory(offset: Int(offset), length: Int(length)))
        #expect(String(decoding: input, as: UTF8.self) == "hello")
        let output = input.map { byte in
            byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z") ? byte - 32 : byte
        }
        #expect(try caller.writeMemory(offset: Int(offset), bytes: output))
        return [.i32(length)]
    }
    let instance = try linker.instantiate(store: store, module: module)

    #expect(try instance.exportedFunction(named: "run").call() == [.i32(1)])
}

@Test func hostFunctionCallerReportsMemoryBoundsErrors() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (import "host" "read_oob" (func $read_oob))
          (memory (export "memory") 1)
          (func (export "run")
            call $read_oob))
        """
    )
    let linker = try Linker(engine: engine)
    try linker.defineFunction(module: "host", name: "read_oob", type: FunctionType()) { caller, _ in
        try #expect(throws: WasmtimeError.memoryAccessOutOfBounds(offset: -1, length: 1, memorySize: 0)) {
            _ = try caller.readMemory(offset: -1, length: 1)
        }
        try #expect(throws: WasmtimeError.memoryAccessOutOfBounds(offset: -1, length: 1, memorySize: 0)) {
            _ = try caller.writeMemory(offset: -1, bytes: [1])
        }
        try #expect(throws: WasmtimeError.memoryAccessOutOfBounds(offset: 65536, length: 1, memorySize: 65536)) {
            _ = try caller.writeMemory(offset: 65536, bytes: [1])
        }
        _ = try caller.readMemory(offset: 65536, length: 1)
        return []
    }
    let instance = try linker.instantiate(store: store, module: module)

    do {
        _ = try instance.exportedFunction(named: "run").call()
        Issue.record("expected memory bounds trap")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("memory access out of bounds"))
    }
    #expect(
        WasmtimeError.memoryAccessOutOfBounds(offset: 1, length: 2, memorySize: 3).description ==
            "memory access out of bounds: offset 1, length 2, memory size 3"
    )
}

@Test func hostFunctionCallerExpiresAfterCallbackReturns() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let escapedCaller = LockedCallerBox()
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (import "host" "capture" (func $capture))
          (memory (export "memory") 1)
          (func (export "run")
            call $capture))
        """
    )
    let linker = try Linker(engine: engine)
    try linker.defineFunction(module: "host", name: "capture", type: FunctionType()) { caller, _ in
        escapedCaller.set(caller)
        let kind = try caller.exportKind(named: "memory")
        #expect(kind == .memory)
        return []
    }
    let instance = try linker.instantiate(store: store, module: module)
    #expect(try instance.exportedFunction(named: "run").call() == [])

    let caller = try #require(escapedCaller.get())
    #expect(throws: WasmtimeError.callerExpired) {
        _ = try caller.exportKind(named: "memory")
    }
    #expect(throws: WasmtimeError.callerExpired) {
        _ = try caller.readMemory(offset: 0, length: 1)
    }
    #expect(throws: WasmtimeError.callerExpired) {
        _ = try caller.writeMemory(offset: 0, bytes: [1])
    }
}

@Test func componentLinkerInstantiatesAndCallsZeroParameterZeroResultFunctions() throws {
    let config = try Config()
    config.isComponentModelEnabled = true
    let engine = try Engine(config: config)
    let store = try Store(engine: engine)
    let component = try Component(engine: engine, wat: componentRunWat)
    let linker = try ComponentLinker(engine: engine)

    linker.allowsShadowing = true
    let instance = try linker.instantiate(store: store, component: component)
    try instance.exportedFunction(named: "run").call()

    try expectSpecificError(.missingExport("missing")) {
        _ = try instance.exportedFunction(named: "missing")
    }
}

@Test func componentExportedFunctionReportsWrongKindExports() throws {
    let config = try Config()
    config.isComponentModelEnabled = true
    let engine = try Engine(config: config)
    let store = try Store(engine: engine)
    let component = try Component(
        engine: engine,
        wat: """
        (component
          (instance $empty)
          (export "not-func" (instance $empty)))
        """
    )
    let instance = try ComponentLinker(engine: engine).instantiate(store: store, component: component)

    do {
        _ = try instance.exportedFunction(named: "not-func")
        Issue.record("expected wrong export kind error")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("expected func"))
    }
}

@Test func componentLinkerRegistersWasiP2AndHTTP() throws {
    let config = try Config()
    config.isComponentModelEnabled = true
    let engine = try Engine(config: config)
    let store = try Store(engine: engine)
    let wasi = try WasiConfig()
    try store.setWasi(wasi)
    store.setWasiHTTP()

    let linker = try ComponentLinker(engine: engine)
    try linker.addWasiP2()
    try linker.addWasiHTTP()
}
