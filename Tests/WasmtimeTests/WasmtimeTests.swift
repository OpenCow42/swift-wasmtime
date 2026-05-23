import Foundation
import Testing
@preconcurrency import CWasmtime
@testable import Wasmtime

@Test func packageImportsAndCreatesEngineStore() throws {
    let engine = try Engine()
    _ = try Store(engine: engine)
    acceptsSendable(engine)
    acceptsSendable(InterruptionOptions())
    acceptsSendable(EngineOptions())
    acceptsSendable(ResourceLimits())
    acceptsSendable(EpochDeadlineAction.continue(ticksBeyondCurrent: 1))
    acceptsSendable(CompilationStrategy.automatic)
    acceptsSendable(CraneliftOptimizationLevel.speed)
    acceptsSendable(try MemoryType(minimumPages: 0))
    acceptsSendable(try GlobalType(content: .i32))
    acceptsSendable(try TableType(minimumElements: 0))
    acceptsSendable(TableElementKind.functionReference)
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
    acceptsSendable(TrapCode.unreachableCodeReached)
    acceptsSendable(WasmFrame(functionIndex: 0, functionOffset: 1, moduleOffset: 2))
    acceptsSendable(WasmTrace())
    acceptsSendable(WasmtimeError.missingExport("missing"))
    acceptsSendable(ModuleGlobalType(content: .i32))
    acceptsSendable(ModuleTableType(minimumElements: 0))
    acceptsSendable(ModuleMemoryType(minimumPages: 0))
    acceptsSendable(ModuleExternType.function(FunctionType()))
    acceptsSendable(ModuleImport(module: "host", name: "run", type: .function(FunctionType())))
    acceptsSendable(ModuleExport(name: "run", type: .function(FunctionType())))

    let emptyCaller = Caller(raw: nil)
    #expect(try emptyCaller.exportKind(named: "memory") == nil)
    #expect(try emptyCaller.readMemory(offset: 0, length: 0) == nil)
    #expect(try emptyCaller.writeMemory(offset: 0, bytes: []) == false)
}

@Test func compilesWatWasmBytesAndData() throws {
    let engine = try Engine()
    let wasm = try WasmText.compile("(module)")

    try Module.validate(engine: engine, wasm: wasm)
    try Module.validate(engine: engine, data: Data(wasm))

    let bytesModule = try Module(engine: engine, wasm: wasm)
    acceptsSendable(bytesModule)

    let dataModule = try Module(engine: engine, data: Data(wasm))
    acceptsSendable(dataModule)

    let emptyModule = try Module(engine: engine, wat: "(module)")
    #expect(try emptyModule.imports().isEmpty)
    #expect(try emptyModule.exports().isEmpty)
}

@Test func moduleValidationRejectsInvalidWasm() throws {
    let engine = try Engine()

    try expectWasmtimeError {
        try Module.validate(engine: engine, wasm: [0, 1, 2, 3])
    }

    try expectWasmtimeError {
        try Module.validate(engine: engine, data: Data([0, 1, 2, 3]))
    }
}

@Test func moduleCloneCanBeInstantiatedAndKeepsMetadata() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (import "host" "value" (global i32))
          (func (export "answer") (result i32)
            global.get 0))
        """
    )

    let clone = try module.clone()
    acceptsSendable(clone)

    #expect(try clone.imports() == module.imports())
    #expect(try clone.exports() == module.exports())

    let global = try Global(store: store, type: GlobalType(content: .i32), value: .i32(42))
    let linker = try Linker(engine: engine)
    try linker.define(module: "host", name: "value", global: global)

    let instance = try linker.instantiate(store: store, module: clone)
    #expect(try instance.exportedFunction(named: "answer").call() == [.i32(42)])
}

@Test func moduleSerializationRoundTripsThroughBytesDataAndFile() throws {
    let engine = try Engine()
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (import "host" "value" (global i32))
          (func (export "answer") (result i32)
            global.get 0))
        """
    )

    let serialized = try module.serialize()
    #expect(!serialized.isEmpty)

    let bytesModule = try Module.deserialize(engine: engine, serialized: serialized)
    let dataModule = try Module.deserialize(engine: engine, data: Data(serialized))

    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build", isDirectory: true)
        .appendingPathComponent("swift-wasmtime-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let file = directory.appendingPathComponent("module.cwasm")
    try Data(serialized).write(to: file)
    let fileModule = try Module.deserializeFile(engine: engine, path: file.path)

    #expect(try bytesModule.imports() == module.imports())
    #expect(try bytesModule.exports() == module.exports())
    #expect(try dataModule.imports() == module.imports())
    #expect(try dataModule.exports() == module.exports())
    #expect(try fileModule.imports() == module.imports())
    #expect(try fileModule.exports() == module.exports())

    let store = try Store(engine: engine)
    let linker = try Linker(engine: engine)
    let global = try Global(store: store, type: GlobalType(content: .i32), value: .i32(42))
    try linker.define(module: "host", name: "value", global: global)

    let instance = try linker.instantiate(store: store, module: bytesModule)
    #expect(try instance.exportedFunction(named: "answer").call() == [.i32(42)])
}

@Test func moduleDeserializationRejectsInvalidArtifacts() throws {
    let engine = try Engine()

    try expectWasmtimeError {
        _ = try Module.deserialize(engine: engine, serialized: [0, 1, 2, 3])
    }

    try expectWasmtimeError {
        _ = try Module.deserialize(engine: engine, data: Data([0, 1, 2, 3]))
    }

    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build", isDirectory: true)
        .appendingPathComponent("swift-wasmtime-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let file = directory.appendingPathComponent("invalid.cwasm")
    try Data([0, 1, 2, 3]).write(to: file)
    try expectWasmtimeError {
        _ = try Module.deserializeFile(engine: engine, path: file.path)
    }
}

@Test func modulesExposeImportAndExportTypeMetadata() throws {
    let engine = try Engine()
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (import "host" "function" (func $imported_function (param i32 i64) (result f32)))
          (import "host" "global" (global $imported_global (mut i32)))
          (import "host" "table" (table $imported_table 2 4 funcref))
          (import "host" "memory" (memory $imported_memory 1 3))
          (func $exported_function (export "function") (param f64) (result i64)
            i64.const 42)
          (global $exported_global (export "global") i32 (i32.const 7))
          (table $exported_table (export "table") 1 2 funcref)
          (memory $exported_memory (export "memory") 1 2))
        """
    )

    let imports = try module.imports()
    #expect(imports.map(\.module) == ["host", "host", "host", "host"])
    #expect(imports.map(\.name) == ["function", "global", "table", "memory"])
    #expect(imports.map(\.kind) == [.function, .global, .table, .memory])
    #expect(imports[0].type == .function(FunctionType(parameters: [.i32, .i64], results: [.f32])))
    #expect(imports[1].type == .global(ModuleGlobalType(content: .i32, isMutable: true)))
    #expect(imports[2].type == .table(ModuleTableType(element: .functionReference, minimumElements: 2, maximumElements: 4)))
    #expect(imports[3].type == .memory(ModuleMemoryType(minimumPages: 1, maximumPages: 3)))

    let exports = try module.exports()
    #expect(exports.map(\.name) == ["function", "global", "table", "memory"])
    #expect(exports.map(\.kind) == [.function, .global, .table, .memory])
    #expect(exports[0].type == .function(FunctionType(parameters: [.f64], results: [.i64])))
    #expect(exports[1].type == .global(ModuleGlobalType(content: .i32)))
    #expect(exports[2].type == .table(ModuleTableType(element: .functionReference, minimumElements: 1, maximumElements: 2)))
    #expect(exports[3].type == .memory(ModuleMemoryType(minimumPages: 1, maximumPages: 2)))
}

@Test func moduleTypeMetadataPreservesUnsupportedReferenceSignatures() throws {
    let engine = try Engine()
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (import "host" "takes_ref" (func (param funcref)))
          (func (export "returns_ref") (result funcref)
            ref.null func)
          (global (export "ref_global") funcref (ref.null func)))
        """
    )

    let imports = try module.imports()
    #expect(imports.count == 1)
    #expect(imports[0].module == "host")
    #expect(imports[0].name == "takes_ref")
    #expect(imports[0].type == .unsupported(.function))
    #expect(imports[0].kind == .function)

    let exports = try module.exports()
    #expect(exports.map(\.name) == ["returns_ref", "ref_global"])
    #expect(exports.map(\.type) == [.unsupported(.function), .unsupported(.global)])
    #expect(exports.map(\.kind) == [.function, .global])
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
    config.consumesFuel = true
    config.usesEpochInterruption = true
    config.memoryMayMove = true
    config.signalsBasedTraps = true
    config.setMemoryReservation(1 << 32)
    config.setMemoryGuardSize(1 << 16)
    config.setMemoryReservationForGrowth(1 << 20)
    config.setMaxWasmStack(1 << 20)
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
        memoryReservationForGrowth: 1 << 20,
        interruption: InterruptionOptions(
            consumesFuel: true,
            usesEpochInterruption: true,
            maxWasmStack: 1 << 20
        )
    )
    acceptsSendable(options)

    _ = try Engine(options: options)
    #expect(options.interruption.consumesFuel)
    #expect(options.interruption.usesEpochInterruption)
    #expect(options.interruption.maxWasmStack == 1 << 20)

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

@Test func storeResourceLimitsFuelEpochAndGarbageCollection() throws {
    let disabledFuelStore = try Store(engine: Engine())
    try expectWasmtimeError {
        try disabledFuelStore.setFuel(1)
    }
    try expectWasmtimeError {
        _ = try disabledFuelStore.fuel()
    }

    let config = try Config()
    config.consumesFuel = true
    config.usesEpochInterruption = true
    let engine = try Engine(config: config)
    let store = try Store(engine: engine)
    store.setEpochDeadline(ticksBeyondCurrent: 1_000)
    try store.collectGarbage()

    try store.setFuel(10_000)
    #expect(try store.fuel() == 10_000)

    let module = try Module(engine: engine, wat: countedLoopWat)
    let instance = try Instance(store: store, module: module)
    let count = try instance.exportedFunction(named: "count")
    #expect(try count.call([.i32(20)]) == [.i32(20)])
    #expect(try store.fuel() < 10_000)

    try store.setFuel(0)
    try expectWasmtimeError {
        _ = try count.call([.i32(1)])
    }

    try store.setFuel(10_000)
    store.setEpochDeadline(ticksBeyondCurrent: 1)
    engine.incrementEpoch()
    try expectWasmtimeError {
        _ = try count.call([.i32(1)])
    }
}

@Test func storeResourceLimitsPreventFutureInstances() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    store.setResourceLimits(ResourceLimits(instances: 1))
    let module = try Module(engine: engine, wat: "(module)")

    _ = try Instance(store: store, module: module)
    try expectWasmtimeError {
        _ = try Instance(store: store, module: module)
    }
}

@Test func epochDeadlineCallbacksCanContinueOrTerminateExecution() throws {
    let continueConfig = try Config()
    continueConfig.usesEpochInterruption = true
    let continueEngine = try Engine(config: continueConfig)
    let continueStore = try Store(engine: continueEngine)
    let callbackCount = LockedInt()
    continueStore.setEpochDeadline(ticksBeyondCurrent: 0)
    continueStore.setEpochDeadlineCallback { currentDeadlineDelta in
        #expect(currentDeadlineDelta == 0)
        callbackCount.increment()
        return .continue(ticksBeyondCurrent: 1_000)
    }

    let continueModule = try Module(engine: continueEngine, wat: countedLoopWat)
    let continueInstance = try Instance(store: continueStore, module: continueModule)
    #expect(try continueInstance.exportedFunction(named: "count").call([.i32(100)]) == [.i32(100)])
    #expect(callbackCount.value() > 0)

    let terminateConfig = try Config()
    terminateConfig.usesEpochInterruption = true
    let terminateEngine = try Engine(config: terminateConfig)
    let terminateStore = try Store(engine: terminateEngine)
    terminateStore.setEpochDeadline(ticksBeyondCurrent: 0)
    terminateStore.setEpochDeadlineCallback { _ in
        throw WasmtimeError.api(message: "deadline stopped", exitStatus: nil)
    }
    let terminateModule = try Module(engine: terminateEngine, wat: countedLoopWat)
    let terminateInstance = try Instance(store: terminateStore, module: terminateModule)

    do {
        _ = try terminateInstance.exportedFunction(named: "count").call([.i32(100)])
        Issue.record("expected epoch callback error")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("deadline stopped"))
    }
}

@Test func runtimeActorManagesResourceControls() async throws {
    let runtime = try WasmtimeRuntime(
        options: EngineOptions(interruption: InterruptionOptions(consumesFuel: true, usesEpochInterruption: true)),
        resourceLimits: ResourceLimits(instances: 2)
    )
    await runtime.setEpochDeadline(ticksBeyondCurrent: 1_000)
    try await runtime.collectGarbage()
    try await runtime.setFuel(10_000)
    #expect(try await runtime.fuel() == 10_000)

    let module = try await runtime.compileModule(wat: countedLoopWat)
    let instance = try await runtime.instantiate(module)
    #expect(try await runtime.call("count", in: instance, arguments: [.i32(5)]) == [.i32(5)])
    #expect(try await runtime.fuel() < 10_000)

    await runtime.setEpochDeadline(ticksBeyondCurrent: 1)
    await runtime.incrementEpoch()
    do {
        _ = try await runtime.call("count", in: instance, arguments: [.i32(1)])
        Issue.record("expected epoch interruption error")
    } catch let error as WasmtimeError {
        #expect(!error.description.isEmpty)
    }

    let callbackRuntime = try WasmtimeRuntime(
        options: EngineOptions(interruption: InterruptionOptions(usesEpochInterruption: true))
    )
    let callbackCount = LockedInt()
    await callbackRuntime.setEpochDeadline(ticksBeyondCurrent: 0)
    await callbackRuntime.setEpochDeadlineCallback { _ in
        callbackCount.increment()
        return .continue(ticksBeyondCurrent: 1_000)
    }
    let callbackInstance = try await callbackRuntime.instantiate(wat: countedLoopWat)
    #expect(try await callbackRuntime.call("count", in: callbackInstance, arguments: [.i32(10)]) == [.i32(10)])
    #expect(callbackCount.value() > 0)

    let existingEngineRuntime = try WasmtimeRuntime(engine: Engine(), resourceLimits: ResourceLimits(instances: 1))
    await existingEngineRuntime.setResourceLimits(ResourceLimits(instances: 2))
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

@Test func linearMemoriesCanBeCreatedExportedReadWrittenAndGrown() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)

    let unboundedType = try MemoryType(minimumPages: 0)
    #expect(unboundedType.minimumPages == 0)
    #expect(unboundedType.maximumPages == nil)
    #expect(!unboundedType.is64)
    #expect(!unboundedType.isShared)
    #expect(unboundedType.pageSize == 65_536)
    #expect(unboundedType.pageSizeLog2 == 16)

    let boundedType = try MemoryType(minimumPages: 1, maximumPages: 2)
    let memory = try Memory(store: store, type: boundedType)
    #expect(memory.size == 1)
    #expect(memory.dataSize == 65_536)
    #expect(memory.pageSize == 65_536)
    #expect(memory.pageSizeLog2 == 16)

    let reflectedType = try memory.type()
    #expect(reflectedType.minimumPages == 1)
    #expect(reflectedType.maximumPages == 2)

    #expect(try memory.read(offset: 0, length: 0) == [])
    try memory.write(offset: 0, bytes: [])
    try memory.write(offset: 4, bytes: Array("host".utf8))
    #expect(try memory.read(offset: 4, length: 4) == Array("host".utf8))

    try #expect(throws: WasmtimeError.memoryAccessOutOfBounds(offset: -1, length: 1, memorySize: 0)) {
        _ = try memory.read(offset: -1, length: 1)
    }
    try #expect(throws: WasmtimeError.memoryAccessOutOfBounds(offset: -1, length: 1, memorySize: 0)) {
        try memory.write(offset: -1, bytes: [1])
    }
    try #expect(throws: WasmtimeError.memoryAccessOutOfBounds(offset: 65_536, length: 1, memorySize: 65_536)) {
        _ = try memory.read(offset: 65_536, length: 1)
    }
    try #expect(throws: WasmtimeError.memoryAccessOutOfBounds(offset: 65_536, length: 1, memorySize: 65_536)) {
        try memory.write(offset: 65_536, bytes: [1])
    }

    #expect(try memory.grow(by: 1) == 1)
    #expect(memory.size == 2)
    try expectWasmtimeError {
        _ = try memory.grow(by: 1)
    }

    let module = try Module(
        engine: engine,
        wat: """
        (module
          (memory (export "memory") 1 2)
          (data (i32.const 8) "guest")
          (func (export "run")))
        """
    )
    let instance = try Instance(store: store, module: module)
    let exported = try instance.exportedMemory()
    #expect(try exported.read(offset: 8, length: 5) == Array("guest".utf8))

    try expectSpecificError(.missingExport("missing")) {
        _ = try instance.exportedMemory(named: "missing")
    }
    do {
        _ = try instance.exportedMemory(named: "run")
        Issue.record("expected wrong export kind")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("expected memory"))
    }
}

@Test func globalsReadImmutableExportsAndReflectNumericTypes() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (global (export "answer") i32 (i32.const 42))
          (global (export "wide") i64 (i64.const 84))
          (global (export "float") f32 (f32.const 1.5))
          (global (export "double") f64 (f64.const 2.5)))
        """
    )
    let instance = try Instance(store: store, module: module)

    let answer = try instance.exportedGlobal(named: "answer")
    #expect(try answer.get() == .i32(42))
    let answerType = try answer.type()
    #expect(answerType.content == .i32)
    #expect(!answerType.isMutable)

    let wideType = try instance.exportedGlobal(named: "wide").type()
    #expect(wideType.content == .i64)
    #expect(!wideType.isMutable)
    #expect(try instance.exportedGlobal(named: "wide").get() == .i64(84))

    let floatType = try instance.exportedGlobal(named: "float").type()
    #expect(floatType.content == .f32)
    #expect(!floatType.isMutable)
    #expect(try instance.exportedGlobal(named: "float").get() == .f32(1.5))

    let doubleType = try instance.exportedGlobal(named: "double").type()
    #expect(doubleType.content == .f64)
    #expect(!doubleType.isMutable)
    #expect(try instance.exportedGlobal(named: "double").get() == .f64(2.5))

    try expectWasmtimeError {
        try answer.set(.i32(7))
    }
}

@Test func mutableGlobalsCanBeSetFromSwift() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (global (export "counter") (mut i32) (i32.const 1))
          (func (export "read") (result i32)
            global.get 0))
        """
    )
    let instance = try Instance(store: store, module: module)
    let counter = try instance.exportedGlobal(named: "counter")

    let counterType = try counter.type()
    #expect(counterType.content == .i32)
    #expect(counterType.isMutable)
    #expect(try counter.get() == .i32(1))

    try counter.set(.i32(9))
    #expect(try counter.get() == .i32(9))
    #expect(try instance.exportedFunction(named: "read").call() == [.i32(9)])

    try expectWasmtimeError {
        try counter.set(.i64(9))
    }
}

@Test func globalsReportMissingAndWrongKindExports() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (func (export "run"))
          (memory (export "memory") 1))
        """
    )
    let instance = try Instance(store: store, module: module)

    try expectSpecificError(.missingExport("missing")) {
        _ = try instance.exportedGlobal(named: "missing")
    }
    do {
        _ = try instance.exportedGlobal(named: "run")
        Issue.record("expected wrong export kind")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("expected global"))
    }
    do {
        _ = try instance.exportedFunction(named: "memory")
        Issue.record("expected wrong export kind")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("expected func"))
    }
}

@Test func linkerDefinesAndGetsStoreBoundGlobals() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let global = try Global(store: store, type: GlobalType(content: .i32, isMutable: true), value: .i32(11))
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (import "host" "global" (global $global (mut i32)))
          (func (export "read") (result i32)
            global.get $global)
          (func (export "write") (param i32)
            local.get 0
            global.set $global))
        """
    )
    let linker = try Linker(engine: engine)
    try linker.define(module: "host", name: "global", global: global)

    switch try #require(linker.get(store: store, module: "host", name: "global")) {
    case .global(let linkedGlobal):
        #expect(try linkedGlobal.get() == .i32(11))
        try linkedGlobal.set(.i32(12))
    default:
        Issue.record("expected global extern")
    }

    let instance = try linker.instantiate(store: store, module: module)
    #expect(try instance.exportedFunction(named: "read").call() == [.i32(12)])
    #expect(try instance.exportedFunction(named: "write").call([.i32(13)]) == [])
    #expect(try global.get() == .i32(13))
}

@Test func instancesExposeGenericExternsForFunctionsGlobalsMemoriesAndUnsupportedKinds() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (func (export "answer") (result i32) i32.const 42)
          (memory (export "memory") 1)
          (global (export "global") i32 (i32.const 7))
          (table (export "table") 1 funcref))
        """
    )
    let instance = try Instance(store: store, module: module)

    switch try instance.export(named: "answer") {
    case .function(let function):
        #expect(try function.call() == [.i32(42)])
    default:
        Issue.record("expected function extern")
    }

    switch try instance.export(named: "memory") {
    case .memory(let memory):
        #expect(memory.size == 1)
    default:
        Issue.record("expected memory extern")
    }

    switch try instance.export(named: "global") {
    case .global(let global):
        #expect(try global.get() == .i32(7))
    default:
        Issue.record("expected global extern")
    }

    switch try instance.export(named: "table") {
    case .table(let table):
        #expect(table.size == 1)
    default:
        Issue.record("expected table extern")
    }

    let global = try instance.exportedGlobal(named: "global")
    #expect(try global.get() == .i32(7))
    let table = try instance.exportedTable(named: "table")
    #expect(table.size == 1)

    try expectSpecificError(.missingExport("missing")) {
        _ = try instance.export(named: "missing")
    }
}

@Test func instancesExposeExportsByIndexInExportOrder() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (func $answer (result i32) i32.const 42)
          (global $global i32 (i32.const 7))
          (table $table 1 funcref)
          (memory $memory 1)
          (export "answer" (func $answer))
          (export "global" (global $global))
          (export "table" (table $table))
          (export "memory" (memory $memory)))
        """
    )
    let instance = try Instance(store: store, module: module)

    let function = try #require(try instance.export(at: 0))
    #expect(function.name == "answer")
    #expect(function.kind == .function)
    switch function.extern {
    case .function(let answer):
        #expect(try answer.call() == [.i32(42)])
    default:
        Issue.record("expected function export")
    }

    let global = try #require(try instance.export(at: 1))
    #expect(global.name == "global")
    #expect(global.kind == .global)
    switch global.extern {
    case .global(let value):
        #expect(try value.get() == .i32(7))
    default:
        Issue.record("expected global export")
    }

    let table = try #require(try instance.export(at: 2))
    #expect(table.name == "table")
    #expect(table.kind == .table)
    switch table.extern {
    case .table(let table):
        #expect(table.size == 1)
    default:
        Issue.record("expected table export")
    }

    let memory = try #require(try instance.export(at: 3))
    #expect(memory.name == "memory")
    #expect(memory.kind == .memory)
    switch memory.extern {
    case .memory(let memory):
        #expect(memory.size == 1)
    default:
        Issue.record("expected memory export")
    }

    #expect(try instance.export(at: 4) == nil)
    #expect(try instance.export(at: -1) == nil)

    let exports = try instance.exports()
    #expect(exports.map(\.name) == ["answer", "global", "table", "memory"])
    #expect(exports.map(\.kind) == [.function, .global, .table, .memory])
}

@Test func tablesExposeTypeSizeNullElementsAndGrowth() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (table (export "table") 1 3 funcref))
        """
    )
    let instance = try Instance(store: store, module: module)
    let table = try instance.exportedTable(named: "table")

    let tableType = try table.type()
    #expect(tableType.element == .functionReference)
    #expect(tableType.element.description == "funcref")
    #expect(tableType.minimumElements == 1)
    #expect(tableType.maximumElements == 3)
    #expect(table.size == 1)
    #expect(try table.get(index: 1) == nil)

    switch try table.get(index: 0) {
    case .nullFunctionReference:
        break
    default:
        Issue.record("expected null funcref element")
    }

    #expect(try table.grow(by: 1) == 1)
    #expect(table.size == 2)
    switch try table.get(index: 1) {
    case .nullFunctionReference:
        break
    default:
        Issue.record("expected grown null funcref element")
    }

    try expectWasmtimeError {
        try table.grow(by: 2)
    }
}

@Test func tablesCanStoreAndLoadFunctionReferences() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (table (export "table") 1 funcref)
          (func (export "answer") (result i32)
            i32.const 42))
        """
    )
    let instance = try Instance(store: store, module: module)
    let table = try instance.exportedTable(named: "table")
    let answer = try instance.exportedFunction(named: "answer")

    let functionElement = TableElement.function(answer)
    #expect(functionElement.kind == .functionReference)
    try table.set(index: 0, to: functionElement)

    switch try table.get(index: 0) {
    case .function(let function):
        #expect(try function.call() == [.i32(42)])
    default:
        Issue.record("expected function reference element")
    }

    try table.set(index: 0, to: .nullFunctionReference)
    switch try table.get(index: 0) {
    case .nullFunctionReference:
        break
    default:
        Issue.record("expected reset null funcref element")
    }
}

@Test func externalReferenceTablesSupportNullElementsOnly() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let tableType = try TableType(element: .externalReference, minimumElements: 1)
    let table = try Table(store: store, type: tableType)

    #expect(tableType.element == .externalReference)
    #expect(tableType.element.description == "externref")
    #expect(tableType.minimumElements == 1)
    #expect(tableType.maximumElements == nil)
    #expect(table.size == 1)

    let reflectedType = try table.type()
    #expect(reflectedType.element == .externalReference)
    #expect(reflectedType.minimumElements == 1)
    #expect(reflectedType.maximumElements == nil)

    let nullExternal = TableElement.nullExternalReference
    #expect(nullExternal.kind == .externalReference)
    switch try table.get(index: 0) {
    case .nullExternalReference:
        break
    default:
        Issue.record("expected null externref element")
    }

    try table.set(index: 0, to: nullExternal)
    #expect(try table.grow(by: 1, initialElement: nullExternal) == 1)
    #expect(table.size == 2)

    try expectWasmtimeError {
        try table.set(index: 0, to: .nullFunctionReference)
    }
}

@Test func tableUnsupportedElementKindsReportErrors() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let unknownKind = TableElementKind(rawValue: 255)

    #expect(unknownKind == .unknown(255))
    #expect(unknownKind.description == "unknown(255)")
    try expectSpecificError(.unsupportedValueKind(255)) {
        _ = try TableElement.null(for: unknownKind)
    }
    try expectSpecificError(.unsupportedValueKind(255)) {
        _ = try TableType(element: unknownKind, minimumElements: 1)
    }

    var rawValue = wasmtime_val_t()
    rawValue.kind = 99
    try expectSpecificError(.unsupportedValueKind(99)) {
        _ = try TableElement(store: store, rawValue: rawValue)
    }
}

@Test func tablesReportMissingAndWrongKindExports() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (global (export "global") i32 (i32.const 1))
          (func (export "run"))
          (memory (export "memory") 1))
        """
    )
    let instance = try Instance(store: store, module: module)

    try expectSpecificError(.missingExport("missing")) {
        _ = try instance.exportedTable(named: "missing")
    }
    do {
        _ = try instance.exportedTable(named: "run")
        Issue.record("expected wrong export kind")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("expected table"))
    }
    do {
        _ = try instance.exportedTable(named: "memory")
        Issue.record("expected wrong export kind")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("is memory"))
    }
    do {
        _ = try instance.exportedTable(named: "global")
        Issue.record("expected wrong export kind")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("is global"))
    }
}

@Test func linkerDefinesAndGetsStoreBoundTables() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let table = try Table(
        store: store,
        type: TableType(element: .functionReference, minimumElements: 1, maximumElements: 2)
    )
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (import "host" "table" (table 1 2 funcref)))
        """
    )
    let linker = try Linker(engine: engine)
    try linker.define(module: "host", name: "table", table: table)

    switch try #require(linker.get(store: store, module: "host", name: "table")) {
    case .table(let linkedTable):
        #expect(linkedTable.size == 1)
        #expect(try linkedTable.grow(by: 1) == 1)
    default:
        Issue.record("expected table extern")
    }

    _ = try linker.instantiate(store: store, module: module)
    #expect(table.size == 2)
}

@Test func linkerDefinesStoreBoundMemories() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let memory = try Memory(store: store, type: MemoryType(minimumPages: 1))
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (import "host" "mem" (memory 1))
          (func (export "write")
            i32.const 0
            i32.const 65
            i32.store8))
        """
    )
    let linker = try Linker(engine: engine)
    try linker.define(module: "host", name: "mem", memory: memory)
    switch try #require(linker.get(store: store, module: "host", name: "mem")) {
    case .memory(let linkedMemory):
        #expect(linkedMemory.size == 1)
    default:
        Issue.record("expected memory extern")
    }
    #expect(linker.get(store: store, module: "host", name: "missing") == nil)
    let instance = try linker.instantiate(store: store, module: module)

    #expect(try instance.exportedFunction(named: "write").call() == [])
    #expect(try memory.read(offset: 0, length: 1) == [65])
}

@Test func linkerGetsFunctionAndInstanceExterns() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let linker = try Linker(engine: engine)
    try linker.defineFunction(module: "host", name: "answer", results: [.i32]) { _, _ in
        [.i32(42)]
    }

    switch try #require(linker.get(store: store, module: "host", name: "answer")) {
    case .function(let function):
        #expect(try function.type() == FunctionType(results: [.i32]))
        #expect(try function.call() == [.i32(42)])
    default:
        Issue.record("expected function extern")
    }

    let providerModule = try Module(
        engine: engine,
        wat: """
        (module
          (global (export "global") i32 (i32.const 1))
          (memory (export "memory") 1))
        """
    )
    let provider = try Instance(store: store, module: providerModule)
    try linker.defineInstance(store: store, name: "provider", instance: provider)

    #expect(linker.get(store: store, module: "provider", name: "global")?.kind == .global)
    #expect(linker.get(store: store, module: "provider", name: "memory")?.kind == .memory)
}

@Test func linkerCloneCopiesDefinitionsAndKeepsLaterDefinitionsIndependent() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let linker = try Linker(engine: engine)
    linker.allowsShadowing = true
    try linker.defineFunction(module: "host", name: "answer", results: [.i32]) { _, _ in
        [.i32(42)]
    }

    let clone = try linker.clone()
    switch try #require(clone.get(store: store, module: "host", name: "answer")) {
    case .function(let function):
        #expect(try function.call() == [.i32(42)])
    default:
        Issue.record("expected cloned function extern")
    }

    try clone.defineFunction(module: "host", name: "answer", results: [.i32]) { _, _ in
        [.i32(7)]
    }
    try clone.defineFunction(module: "host", name: "clone_only", results: [.i32]) { _, _ in
        [.i32(99)]
    }

    switch try #require(clone.get(store: store, module: "host", name: "answer")) {
    case .function(let function):
        #expect(try function.call() == [.i32(7)])
    default:
        Issue.record("expected shadowed cloned function extern")
    }
    switch try #require(linker.get(store: store, module: "host", name: "answer")) {
    case .function(let function):
        #expect(try function.call() == [.i32(42)])
    default:
        Issue.record("expected original function extern")
    }
    #expect(linker.get(store: store, module: "host", name: "clone_only") == nil)
}

@Test func linkerResolvesDefaultFunctionForNamedModule() throws {
    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(
        engine: engine,
        wat: """
        (module
          (func (export "_start")))
        """
    )
    let linker = try Linker(engine: engine)
    try linker.defineModule(store: store, name: "command", module: module)

    let start = try linker.defaultFunction(store: store, moduleName: "command")
    #expect(try start.type() == FunctionType())
    #expect(try start.call() == [])
}

@Test func runtimeActorManagesExportedMemory() async throws {
    let runtime = try WasmtimeRuntime()
    let instance = try await runtime.instantiate(
        wat: """
        (module
          (memory (export "memory") 1 2)
          (data (i32.const 16) "runtime")
          (func (export "not-memory")))
        """
    )

    #expect(try await runtime.exportKind(named: "memory", in: instance) == .memory)
    #expect(try await runtime.exportKind(named: "not-memory", in: instance) == .function)
    #expect(try await runtime.memorySize(in: instance) == 1)
    #expect(try await runtime.memoryDataSize(in: instance) == 65_536)
    #expect(try await runtime.readMemory(in: instance, offset: 16, length: 7) == Array("runtime".utf8))
    try await runtime.writeMemory(in: instance, offset: 16, bytes: Array("MEMORY!".utf8))
    #expect(try await runtime.readMemory(in: instance, offset: 16, length: 7) == Array("MEMORY!".utf8))
    #expect(try await runtime.growMemory(in: instance, by: 1) == 1)
    #expect(try await runtime.memorySize(in: instance) == 2)

    do {
        _ = try await runtime.readMemory(in: RuntimeInstanceID(rawValue: 999), offset: 0, length: 1)
        Issue.record("expected missing runtime instance")
    } catch let error as WasmtimeError {
        #expect(error == .missingRuntimeInstance(RuntimeInstanceID(rawValue: 999)))
    }
    do {
        _ = try await runtime.exportKind(named: "memory", in: RuntimeInstanceID(rawValue: 999))
        Issue.record("expected missing runtime instance")
    } catch let error as WasmtimeError {
        #expect(error == .missingRuntimeInstance(RuntimeInstanceID(rawValue: 999)))
    }
    do {
        _ = try await runtime.readMemory(named: "missing", in: instance, offset: 0, length: 1)
        Issue.record("expected missing memory export")
    } catch let error as WasmtimeError {
        #expect(error == .missingExport("missing"))
    }
    do {
        _ = try await runtime.readMemory(named: "not-memory", in: instance, offset: 0, length: 1)
        Issue.record("expected wrong export kind")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("expected memory"))
    }
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
    let temporary = testTemporaryDirectory()
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
    } catch let error as WasmtimeError {
        #expect(error.description.contains("unknown import"))
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

    let temporary = testTemporaryDirectory()
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
    let temporary = testTemporaryDirectory()
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

private func acceptsSendable<T: Sendable>(_ value: T) {
    _ = value
}

private func testTemporaryDirectory() -> URL {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build", isDirectory: true)
        .appendingPathComponent("test-tmp", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
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

private final class LockedInt: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.withLock {
            storage += 1
        }
    }

    func value() -> Int {
        lock.withLock {
            storage
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

private let countedLoopWat = """
(module
  (func (export "count") (param $n i32) (result i32)
    (local $acc i32)
    block $exit
      loop $loop
        local.get $n
        i32.eqz
        br_if $exit
        local.get $n
        i32.const 1
        i32.sub
        local.set $n
        local.get $acc
        i32.const 1
        i32.add
        local.set $acc
        br $loop
      end
    end
    local.get $acc))
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
