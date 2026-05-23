import Foundation
import Testing
@preconcurrency import CWasmtime
@testable import Wasmtime

@Test func packageImportsAndCreatesEngineStore() throws {
    let engine = try Engine()
    _ = try Store(engine: engine)
    acceptsSendable(engine)
    acceptsSendable(EngineOptions())
    acceptsSendable(CompilationStrategy.automatic)
    acceptsSendable(CraneliftOptimizationLevel.speed)
    acceptsSendable(ValueKind.i32)
    acceptsSendable(FunctionType(parameters: [.i32], results: [.i64]))
    acceptsSendable(Value.i32(1))
    acceptsSendable(WasiDirectoryPermissions.read)
    acceptsSendable(WasiFilePermissions.read)
    acceptsSendable(RuntimeInstanceID(rawValue: 1))
    acceptsSendable(RuntimeComponentInstanceID(rawValue: 1))
    acceptsSendable(RuntimeHostFunction(module: "host", name: "answer", results: [.i32]) { _ in [.i32(42)] })
    acceptsSendable(WasiOptions())
    acceptsSendable(WasiPreopenedDirectory(hostPath: "/", guestPath: "/host"))
    acceptsSendable(Trap(message: "trap", code: nil))
    acceptsSendable(WasmtimeError.missingExport("missing"))

    let emptyCaller = Caller(raw: nil)
    #expect(try emptyCaller.exportKind(named: "memory") == nil)
    #expect(try emptyCaller.readMemory(offset: 0, length: 0) == nil)
    #expect(try emptyCaller.writeMemory(offset: 0, bytes: []) == false)
}

@Test func compilesWatWasmBytesAndData() throws {
    let engine = try Engine()
    let wasm = try WasmText.compile("(module)")

    let bytesModule = try Module(engine: engine, wasm: wasm)
    acceptsSendable(bytesModule)

    let dataModule = try Module(engine: engine, data: Data(wasm))
    acceptsSendable(dataModule)

    _ = try Module(engine: engine, wat: "(module)")
}

@Test func configExposesCompilerTargetMemoryAndTrapOptions() throws {
    let config = try Config()
    config.strategy = .cranelift
    config.craneliftOptimizationLevel = .speedAndSize
    config.isSIMDEnabled = true
    config.isRelaxedSIMDEnabled = true
    config.isRelaxedSIMDDeterministic = true
    config.debugInfo = true
    config.parallelCompilation = false
    config.memoryMayMove = true
    config.signalsBasedTraps = true
    config.setMemoryReservation(1 << 32)
    config.setMemoryGuardSize(1 << 16)
    config.setMemoryReservationForGrowth(1 << 20)
    try config.setTarget(nativeTargetTriple)

    let flagConfig = try Config()
    flagConfig.enableCraneliftFlag(nativeSIMDFlag)
    flagConfig.setCraneliftFlag(nativeSIMDFlag, to: "true")

    #expect(CompilationStrategy.automatic.rawValue == wasmtime_strategy_t(WASMTIME_STRATEGY_AUTO.rawValue))
    #expect(CompilationStrategy.cranelift.rawValue == wasmtime_strategy_t(WASMTIME_STRATEGY_CRANELIFT.rawValue))
    #expect(CraneliftOptimizationLevel.none.rawValue == wasmtime_opt_level_t(WASMTIME_OPT_LEVEL_NONE.rawValue))
    #expect(CraneliftOptimizationLevel.speed.rawValue == wasmtime_opt_level_t(WASMTIME_OPT_LEVEL_SPEED.rawValue))
    #expect(CraneliftOptimizationLevel.speedAndSize.rawValue == wasmtime_opt_level_t(WASMTIME_OPT_LEVEL_SPEED_AND_SIZE.rawValue))

    _ = try Engine(config: config)
}

@Test func engineOptionsBuildSendableConfiguredEngines() throws {
    var options = EngineOptions(
        isComponentModelEnabled: true,
        isSIMDEnabled: true,
        isRelaxedSIMDEnabled: true,
        isRelaxedSIMDDeterministic: true,
        strategy: .cranelift,
        craneliftOptimizationLevel: .speedAndSize,
        memoryMayMove: true,
        signalsBasedTraps: true,
        debugInfo: true,
        parallelCompilation: false,
        target: nativeTargetTriple,
        memoryReservation: 1 << 32,
        memoryGuardSize: 1 << 16,
        memoryReservationForGrowth: 1 << 20
    )
    acceptsSendable(options)

    _ = try Engine(options: options)

    options.enableCraneliftFlag(nativeSIMDFlag)
    options.setCraneliftFlag(nativeSIMDFlag, to: "true")
    options.setMemoryReservation(1 << 32)
    options.setMemoryGuardSize(1 << 16)
    options.setMemoryReservationForGrowth(1 << 20)
    #expect(options.enabledCraneliftFlags.contains(nativeSIMDFlag))
    #expect(options.craneliftFlagValues[nativeSIMDFlag] == "true")
    #expect(options.memoryReservation == 1 << 32)
    #expect(options.memoryGuardSize == 1 << 16)
    #expect(options.memoryReservationForGrowth == 1 << 20)

    var flagOptions = EngineOptions(
        enabledCraneliftFlags: [nativeSIMDFlag],
        craneliftFlagValues: [nativeSIMDFlag: "true"]
    )
    flagOptions.enableCraneliftFlag(nativeSIMDFlag)
    flagOptions.setCraneliftFlag(nativeSIMDFlag, to: "true")
    let flagConfig = try Config()
    try flagConfig.apply(flagOptions)
}

@Test func configReportsInvalidTargetsAndControlsSIMDCompilation() throws {
    let invalidTargetConfig = try Config()
    try expectWasmtimeError {
        try invalidTargetConfig.setTarget("definitely-not-a-real-target")
    }

    try expectWasmtimeError {
        _ = try Engine(options: EngineOptions(target: "definitely-not-a-real-target"))
    }

    let simdDisabledConfig = try Config()
    simdDisabledConfig.isSIMDEnabled = false
    simdDisabledConfig.isRelaxedSIMDEnabled = false
    simdDisabledConfig.isRelaxedSIMDDeterministic = false
    let simdDisabledEngine = try Engine(config: simdDisabledConfig)
    try expectWasmtimeError {
        _ = try Module(engine: simdDisabledEngine, wat: simdWat)
    }

    let simdEnabledConfig = try Config()
    simdEnabledConfig.isSIMDEnabled = true
    let simdEnabledEngine = try Engine(config: simdEnabledConfig)
    _ = try Module(engine: simdEnabledEngine, wat: simdWat)
}

@Test func configEnablesComponentModelAndComponentsCompileFromWatBytesAndData() throws {
    do {
        let config = try Config()
        config.isComponentModelEnabled = true
    }

    let config = try Config()
    config.isComponentModelEnabled = true
    let engine = try Engine(config: config)
    let bytes = try WasmText.compile(componentRunWat)

    let bytesComponent = try Component(engine: engine, wasm: bytes)
    acceptsSendable(bytesComponent)

    _ = try Component(engine: engine, data: Data(bytes))
    _ = try Component(engine: engine, wat: componentRunWat)

    try expectWasmtimeError {
        _ = try Component(engine: engine, wat: "(module)")
    }
}

@Test func invalidWatAndWasmBecomeErrors() throws {
    let engine = try Engine()

    try expectWasmtimeError {
        _ = try WasmText.compile("(module")
    }

    try expectWasmtimeError {
        _ = try Module(engine: engine, wasm: [0, 1, 2, 3])
    }
}

@Test func instantiatesModuleDirectlyAndCallsI32Function() throws {
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

    let instance = try Instance(store: store, module: module)
    let add = try instance.exportedFunction(named: "add")

    #expect(try add.call([.i32(20), .i32(22)]) == [.i32(42)])
}

@Test func runtimeActorCompilesInstantiatesAndCallsFunctions() async throws {
    let runtime = try WasmtimeRuntime(options: EngineOptions())
    let wat = """
    (module
      (func (export "add") (param i32 i32) (result i32)
        local.get 0
        local.get 1
        i32.add)
      (func (export "nothing")))
    """
    let wasm = try WasmText.compile(wat)
    let compiledFromWat = try await runtime.compileModule(wat: wat)
    _ = try await runtime.compileModule(wasm: wasm)
    _ = try await runtime.compileModule(data: Data(wasm))

    let directID = try await runtime.instantiate(compiledFromWat)
    acceptsSendable(directID)
    #expect(directID.description == "runtime instance 0")
    #expect(try await runtime.call("add", in: directID, arguments: [.i32(20), .i32(22)]) == [.i32(42)])
    #expect(try await runtime.call("nothing", in: directID) == [])

    let watID = try await runtime.instantiate(wat: wat)
    let wasmID = try await runtime.instantiate(wasm: wasm)
    let dataID = try await runtime.instantiate(data: Data(wasm))

    async let watResult = runtime.call("add", in: watID, arguments: [.i32(1), .i32(2)])
    async let wasmResult = runtime.call("add", in: wasmID, arguments: [.i32(3), .i32(4)])
    async let dataResult = runtime.call("add", in: dataID, arguments: [.i32(5), .i32(6)])
    #expect(try await watResult == [.i32(3)])
    #expect(try await wasmResult == [.i32(7)])
    #expect(try await dataResult == [.i32(11)])

    do {
        _ = try await runtime.call("add", in: RuntimeInstanceID(rawValue: 999), arguments: [.i32(1), .i32(2)])
        Issue.record("expected missing runtime instance error")
    } catch let error as WasmtimeError {
        #expect(error == .missingRuntimeInstance(RuntimeInstanceID(rawValue: 999)))
    }
}

@Test func runtimeActorCanUseExistingEngine() async throws {
    let engine = try Engine()
    let runtime = try WasmtimeRuntime(engine: engine)
    let instance = try await runtime.instantiate(
        wat: "(module (func (export \"id\") (param i32) (result i32) local.get 0))"
    )

    #expect(try await runtime.call("id", in: instance, arguments: [.i32(9)]) == [.i32(9)])
}

@Test func runtimeActorConfiguresWasiAndInstantiatesWithLinker() async throws {
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("swift-wasmtime-\(UUID().uuidString)", isDirectory: true)
    let sandbox = temporary.appendingPathComponent("sandbox", isDirectory: true)
    let stdout = temporary.appendingPathComponent("stdout.txt")
    let stderr = temporary.appendingPathComponent("stderr.txt")
    let stdin = temporary.appendingPathComponent("stdin.txt")
    try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: stdout.path, contents: Data())
    FileManager.default.createFile(atPath: stderr.path, contents: Data())
    try "stdin\n".write(to: stdin, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: temporary) }

    let allOptions = WasiOptions(
        arguments: ["guest.wasm", "--flag"],
        inheritArguments: true,
        environment: ["A": "B"],
        inheritEnvironment: true,
        standardInputBytes: Array("options-stdin\n".utf8),
        standardInputFile: stdin.path,
        inheritStandardInput: true,
        standardOutputHandler: { output in output.count },
        standardOutputFile: stdout.path,
        inheritStandardOutput: true,
        standardErrorHandler: { output in output.count },
        standardErrorFile: stderr.path,
        inheritStandardError: true,
        preopenedDirectories: [
            WasiPreopenedDirectory(
                hostPath: sandbox.path,
                guestPath: "/sandbox",
                directoryPermissions: [.read, .write],
                filePermissions: [.read, .write]
            )
        ]
    )
    acceptsSendable(allOptions)
    _ = try allOptions.makeConfig()

    let runtime = try WasmtimeRuntime()
    try await runtime.setWasi(WasiOptions(standardOutputFile: stdout.path))
    let module = try await runtime.compileModule(
        wat: """
        (module
          (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
          (memory 1)
          (export "memory" (memory 0))
          (data (i32.const 32) "runtime-wasi\\n")
          (func (export "_start")
            i32.const 0
            i32.const 32
            i32.store
            i32.const 4
            i32.const 13
            i32.store
            i32.const 1
            i32.const 0
            i32.const 1
            i32.const 16
            call $fd_write
            drop))
        """
    )
    let instance = try await runtime.instantiateWithLinker(module, allowsShadowing: true, defineWasi: true)

    #expect(try await runtime.call("_start", in: instance) == [])
    #expect(try String(contentsOf: stdout, encoding: .utf8) == "runtime-wasi\n")
}

@Test func runtimeActorInstantiatesWithUnknownImportHelpers() async throws {
    let runtime = try WasmtimeRuntime()
    let defaultModule = try await runtime.compileModule(
        wat: """
        (module
          (import "env" "answer" (func $answer (result i32)))
          (func (export "run") (result i32)
            call $answer))
        """
    )
    let defaultInstance = try await runtime.instantiateWithLinker(
        defaultModule,
        defineUnknownImportsAsDefaultValues: true
    )
    #expect(try await runtime.call("run", in: defaultInstance) == [.i32(0)])

    let trapModule = try await runtime.compileModule(
        wat: """
        (module
          (import "env" "missing" (func $missing))
          (func (export "run")
            call $missing))
        """
    )
    let trapInstance = try await runtime.instantiateWithLinker(
        trapModule,
        defineUnknownImportsAsTraps: true
    )
    do {
        _ = try await runtime.call("run", in: trapInstance)
        Issue.record("expected unknown-import trap")
    } catch WasmtimeError.api(let message, nil) {
        #expect(message.contains("unknown import"))
    }
}

@Test func runtimeActorInstantiatesWithHostFunctions() async throws {
    let runtime = try WasmtimeRuntime()
    let module = try await runtime.compileModule(
        wat: """
        (module
          (import "host" "double" (func $double (param i32) (result i32)))
          (func (export "run") (result i32)
            i32.const 21
            call $double))
        """
    )
    let instance = try await runtime.instantiateWithLinker(
        module,
        hostFunctions: [
            RuntimeHostFunction(module: "host", name: "double", parameters: [.i32], results: [.i32]) { arguments in
                guard case .i32(let value) = arguments[0] else {
                    throw WasmtimeError.api(message: "unexpected argument", exitStatus: nil)
                }
                return [.i32(value * 2)]
            },
        ]
    )

    #expect(try await runtime.call("run", in: instance) == [.i32(42)])
}

@Test func runtimeActorCompilesInstantiatesAndCallsComponents() async throws {
    let runtime = try WasmtimeRuntime(options: EngineOptions(isComponentModelEnabled: true))
    let componentBytes = try WasmText.compile(componentRunWat)
    let compiledFromWat = try await runtime.compileComponent(wat: componentRunWat)
    _ = try await runtime.compileComponent(wasm: componentBytes)
    _ = try await runtime.compileComponent(data: Data(componentBytes))

    try await runtime.setWasi()
    await runtime.setWasiHTTP()
    let instance = try await runtime.instantiateComponent(
        compiledFromWat,
        allowsShadowing: true,
        addWasiP2: true,
        addWasiHTTP: true
    )
    acceptsSendable(instance)
    #expect(instance.description == "runtime component instance 0")

    try await runtime.call("run", in: instance)

    do {
        try await runtime.call("run", in: RuntimeComponentInstanceID(rawValue: 999))
        Issue.record("expected missing runtime component instance error")
    } catch let error as WasmtimeError {
        #expect(error == .missingRuntimeComponentInstance(RuntimeComponentInstanceID(rawValue: 999)))
    }
}

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
    } catch WasmtimeError.trap(let trap) {
        #expect(trap.description.contains("unreachable"))
        #expect(trap.code != nil)
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
    } catch WasmtimeError.api(let message, nil) {
        #expect(message.contains("unknown import"))
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
    let instance = try linker.instantiate(store: store, module: module)

    #expect(try instance.exportedFunction(named: "run").call() == [.i32(15)])
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
    } catch WasmtimeError.api(let message, nil) {
        #expect(message.contains("host failed"))
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
    } catch WasmtimeError.api(let message, nil) {
        #expect(message.contains("expected 1"))
    }

    let wrongKindLinker = try Linker(engine: engine)
    try wrongKindLinker.defineFunction(module: "host", name: "wrong_count", type: FunctionType(results: [.i32])) { _, _ in
        [.i64(1)]
    }
    let wrongKindInstance = try wrongKindLinker.instantiate(store: store, module: wrongCountModule)
    do {
        _ = try wrongKindInstance.exportedFunction(named: "run").call()
        Issue.record("expected result kind trap")
    } catch WasmtimeError.api(let message, nil) {
        #expect(message.contains("expected i32"))
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
    } catch WasmtimeError.api(let message, nil) {
        #expect(message.contains("memory access out of bounds"))
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

@Test func wasiFileConfigurationReportsFailuresAndSuccesses() throws {
    let config = try WasiConfig()

    try expectSpecificError(.wasiConfigurationFailed("could not open WASI stdin file: /definitely/not/here")) {
        try config.setStandardInputFile("/definitely/not/here")
    }
    try expectSpecificError(.wasiConfigurationFailed("could not open WASI stdout file: /definitely/not/here")) {
        try config.setStandardOutputFile("/definitely/not/here")
    }
    try expectSpecificError(.wasiConfigurationFailed("could not open WASI stderr file: /definitely/not/here")) {
        try config.setStandardErrorFile("/definitely/not/here")
    }
    try expectSpecificError(.wasiConfigurationFailed("could not preopen WASI directory: /definitely/not/here as /missing")) {
        try config.preopenDirectory(hostPath: "/definitely/not/here", guestPath: "/missing")
    }

    let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("swift-wasmtime-\(UUID().uuidString)")
    FileManager.default.createFile(atPath: temporary.path, contents: Data())
    defer { try? FileManager.default.removeItem(at: temporary) }

    try config.setStandardInputFile(temporary.path)
    try config.setStandardOutputFile(temporary.path)
    try config.setStandardErrorFile(temporary.path)
}

@Test func wasiStandardInputBytesAndOutputCallbacksRoundTripData() throws {
    let stdout = LockedOutputBuffer()
    let stderr = LockedOutputBuffer()
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(engine: engine, wat: wasiStdioWat)
    let wasi = try WasiConfig()

    wasi.setStandardInputData(Data("callback-stdin\n".utf8))
    wasi.setStandardOutputHandler { output in
        stdout.append(output)
        return output.count
    }
    wasi.setStandardErrorHandler { output in
        stderr.append(output)
        return output.count
    }
    try store.setWasi(wasi)
    let linker = try Linker(engine: engine)
    try linker.defineWasi()
    let instance = try linker.instantiate(store: store, module: module)

    #expect(try instance.exportedFunction(named: "_start").call() == [])
    #expect(stdout.string() == "callback-stdin\n")
    #expect(stderr.string() == "callback-stderr\n")

    let bytesConfig = try WasiConfig()
    bytesConfig.setStandardInputBytes(Array("bytes\n".utf8))
}

@Test func wasiPreopenedDirectoryGrantsReadAccess() throws {
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("swift-wasmtime-\(UUID().uuidString)", isDirectory: true)
    let sandbox = temporary.appendingPathComponent("sandbox", isDirectory: true)
    let stdout = temporary.appendingPathComponent("stdout.txt")
    try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try "preopen-ok\n".write(to: sandbox.appendingPathComponent("fixture.txt"), atomically: true, encoding: .utf8)

    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (import "wasi_snapshot_preview1" "path_open" (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
          (import "wasi_snapshot_preview1" "fd_read" (func $fd_read (param i32 i32 i32 i32) (result i32)))
          (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
          (memory 1)
          (export "memory" (memory 0))
          (data (i32.const 64) "fixture.txt")
          (data (i32.const 160) "open-failed\\n")
          (data (i32.const 192) "read-failed\\n")
          (func $write (param $ptr i32) (param $len i32)
            i32.const 16
            local.get $ptr
            i32.store
            i32.const 20
            local.get $len
            i32.store
            i32.const 1
            i32.const 16
            i32.const 1
            i32.const 60
            call $fd_write
            drop)
          (func (export "_start") (local $errno i32)
            i32.const 3
            i32.const 0
            i32.const 64
            i32.const 11
            i32.const 0
            i64.const 2
            i64.const 0
            i32.const 0
            i32.const 48
            call $path_open
            local.set $errno
            local.get $errno
            i32.eqz
            if
              i32.const 0
              i32.const 96
              i32.store
              i32.const 4
              i32.const 11
              i32.store
              i32.const 48
              i32.load
              i32.const 0
              i32.const 1
              i32.const 52
              call $fd_read
              local.set $errno
              local.get $errno
              i32.eqz
              if
                i32.const 16
                i32.const 96
                i32.store
                i32.const 20
                i32.const 52
                i32.load
                i32.store
                i32.const 1
                i32.const 16
                i32.const 1
                i32.const 60
                call $fd_write
                drop
              else
                i32.const 192
                i32.const 12
                call $write
              end
            else
              i32.const 160
              i32.const 12
              call $write
            end))
        """
    )
    let wasi = try WasiConfig()
    try wasi.preopenDirectory(
        hostPath: sandbox.path,
        guestPath: "/sandbox",
        directoryPermissions: [.read],
        filePermissions: [.read]
    )
    try wasi.setStandardOutputFile(stdout.path)
    try store.setWasi(wasi)
    let linker = try Linker(engine: engine)
    try linker.defineWasi()
    let instance = try linker.instantiate(store: store, module: module)

    #expect(try instance.exportedFunction(named: "_start").call() == [])
    #expect(try String(contentsOf: stdout, encoding: .utf8) == "preopen-ok\n")
}

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
    #expect(Trap(message: "boom", code: 9).description == "boom (trap code 9)")
    #expect(Trap(message: "boom", code: nil).description == "boom")
    #expect(WasmtimeError.trap(Trap(message: "boom", code: nil)).description == "boom")
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
    var rawValue = wasmtime_val_t()
    rawValue.kind = 99
    try expectSpecificError(.unsupportedValueKind(99)) {
        _ = try Value(rawValue: rawValue)
    }

    let manualError = try #require(wasmtime_error_new("manual error"))
    #expect(WasmtimeError.fromOwned(manualError).description == "manual error")

    let emptyError = try #require(wasmtime_error_new(""))
    #expect(WasmtimeError.fromOwned(emptyError).description == "")

    let message = "host trap"
    let hostTrap = try message.withCString { cMessage in
        try #require(wasmtime_trap_new(cMessage, strlen(cMessage)))
    }
    #expect(Trap.fromOwned(hostTrap).description.contains("host trap"))
}

private func acceptsSendable<T: Sendable>(_ value: T) {
    _ = value
}

private final class LockedOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [UInt8] = []

    func append(_ data: Data) {
        lock.withLock {
            bytes.append(contentsOf: data)
        }
    }

    func string() -> String {
        lock.withLock {
            String(decoding: bytes, as: UTF8.self)
        }
    }
}

private final class LockedCallerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var caller: Caller?

    func set(_ caller: Caller) {
        lock.withLock {
            self.caller = caller
        }
    }

    func get() -> Caller? {
        lock.withLock {
            caller
        }
    }
}

private let nativeSIMDFlag = {
    #if arch(x86_64)
    "has_sse2"
    #elseif arch(arm64)
    "has_neon"
    #else
    "is_pic"
    #endif
}()

private let nativeTargetTriple = {
    #if os(macOS) && arch(arm64)
    "aarch64-apple-darwin"
    #elseif os(macOS) && arch(x86_64)
    "x86_64-apple-darwin"
    #elseif os(Linux) && arch(arm64)
    "aarch64-unknown-linux-gnu"
    #elseif os(Linux) && arch(x86_64)
    "x86_64-unknown-linux-gnu"
    #elseif os(Windows) && arch(arm64)
    "aarch64-pc-windows-msvc"
    #elseif os(Windows) && arch(x86_64)
    "x86_64-pc-windows-msvc"
    #else
    "unknown"
    #endif
}()

private let componentRunWat = """
(component
  (core module $m
    (func (export "run")))
  (core instance $i (instantiate $m))
  (func (export "run") (canon lift (core func $i "run"))))
"""

private let simdWat = """
(module
  (func (export "simd") (result v128)
    v128.const i32x4 1 2 3 4))
"""

private let wasiStdioWat = """
(module
  (import "wasi_snapshot_preview1" "fd_read" (func $fd_read (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory 1)
  (export "memory" (memory 0))
  (data (i32.const 160) "callback-stderr\\n")
  (func $write (param $fd i32) (param $ptr i32) (param $len i32)
    i32.const 24
    local.get $ptr
    i32.store
    i32.const 28
    local.get $len
    i32.store
    local.get $fd
    i32.const 24
    i32.const 1
    i32.const 32
    call $fd_write
    drop)
  (func (export "_start")
    i32.const 0
    i32.const 64
    i32.store
    i32.const 4
    i32.const 32
    i32.store
    i32.const 0
    i32.const 0
    i32.const 1
    i32.const 16
    call $fd_read
    drop
    i32.const 1
    i32.const 64
    i32.const 16
    i32.load
    call $write
    i32.const 2
    i32.const 160
    i32.const 16
    call $write))
"""

private func expectWasmtimeError(_ body: () throws -> Void) throws {
    do {
        try body()
        Issue.record("expected WasmtimeError")
    } catch let error as WasmtimeError {
        #expect(!error.description.isEmpty)
    }
}

private func expectSpecificError(_ expected: WasmtimeError, _ body: () throws -> Void) throws {
    do {
        try body()
        Issue.record("expected \(expected)")
    } catch let error as WasmtimeError {
        #expect(error == expected)
    }
}
