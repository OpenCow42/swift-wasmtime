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
    acceptsSendable(CompilationStrategy.winch)
    acceptsSendable(CraneliftOptimizationLevel.speed)
    acceptsSendable(CraneliftRegallocAlgorithm.backtracking)
    acceptsSendable(ProfilingStrategy.none)
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
    acceptsSendable(RuntimeTableElement.functionReference)
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
    config.craneliftRegallocAlgorithm = .singlePass
    config.isSIMDEnabled = true
    config.isRelaxedSIMDEnabled = true
    config.isRelaxedSIMDDeterministic = true
    config.isSharedMemoryEnabled = true
    config.isTailCallEnabled = true
    config.isReferenceTypesEnabled = true
    config.isFunctionReferencesEnabled = true
    config.isWasmGCEnabled = true
    config.isGCSupportEnabled = true
    config.isBulkMemoryEnabled = true
    config.isMultiValueEnabled = true
    config.isMultiMemoryEnabled = true
    config.isMemory64Enabled = true
    config.isWideArithmeticEnabled = true
    config.areExceptionsEnabled = true
    config.areCustomPageSizesEnabled = true
    config.debugInfo = true
    config.parallelCompilation = false
    config.nativeUnwindInfo = true
    config.usesMachPortsOnMacOS = true
    config.usesMemoryInitCopyOnWrite = true
    config.consumesFuel = true
    config.usesEpochInterruption = true
    config.memoryMayMove = true
    config.signalsBasedTraps = true
    config.isCraneliftDebugVerifierEnabled = true
    config.isCraneliftNaNCanonicalizationEnabled = true
    config.profiler = .none
    config.setMemoryReservation(1 << 32)
    config.setMemoryGuardSize(1 << 16)
    config.setMemoryReservationForGrowth(1 << 20)
    config.setMaxWasmStack(1 << 20)
    try config.setTarget(nativeTargetTriple)

    let flagConfig = try Config()
    flagConfig.enableCraneliftFlag(nativeSIMDFlag)
    flagConfig.setCraneliftFlag(nativeSIMDFlag, to: "true")

    let winchConfig = try Config()
    winchConfig.strategy = .winch

    #expect(CompilationStrategy.automatic.rawValue == wasmtime_strategy_t(WASMTIME_STRATEGY_AUTO.rawValue))
    #expect(CompilationStrategy.cranelift.rawValue == wasmtime_strategy_t(WASMTIME_STRATEGY_CRANELIFT.rawValue))
    #expect(CompilationStrategy.winch.rawValue == wasmtime_strategy_t(WASMTIME_STRATEGY_WINCH.rawValue))
    #expect(CraneliftOptimizationLevel.none.rawValue == wasmtime_opt_level_t(WASMTIME_OPT_LEVEL_NONE.rawValue))
    #expect(CraneliftOptimizationLevel.speed.rawValue == wasmtime_opt_level_t(WASMTIME_OPT_LEVEL_SPEED.rawValue))
    #expect(CraneliftOptimizationLevel.speedAndSize.rawValue == wasmtime_opt_level_t(WASMTIME_OPT_LEVEL_SPEED_AND_SIZE.rawValue))
    #expect(
        CraneliftRegallocAlgorithm.backtracking.rawValue ==
            wasmtime_regalloc_algorithm_t(WASMTIME_REGALLOC_BACKTRACKING.rawValue)
    )
    #expect(
        CraneliftRegallocAlgorithm.singlePass.rawValue ==
            wasmtime_regalloc_algorithm_t(WASMTIME_REGALLOC_SINGLE_PASS.rawValue)
    )
    #expect(ProfilingStrategy.none.rawValue == wasmtime_profiling_strategy_t(WASMTIME_PROFILING_STRATEGY_NONE.rawValue))
    #expect(ProfilingStrategy.jitdump.rawValue == wasmtime_profiling_strategy_t(WASMTIME_PROFILING_STRATEGY_JITDUMP.rawValue))
    #expect(ProfilingStrategy.vtune.rawValue == wasmtime_profiling_strategy_t(WASMTIME_PROFILING_STRATEGY_VTUNE.rawValue))
    #expect(ProfilingStrategy.perfmap.rawValue == wasmtime_profiling_strategy_t(WASMTIME_PROFILING_STRATEGY_PERFMAP.rawValue))

    _ = try Engine(config: config)
}

@Test func engineOptionsBuildSendableConfiguredEngines() throws {
    var options = EngineOptions(
        isComponentModelEnabled: true,
        isSIMDEnabled: true,
        isRelaxedSIMDEnabled: true,
        isRelaxedSIMDDeterministic: true,
        isSharedMemoryEnabled: true,
        isTailCallEnabled: true,
        isReferenceTypesEnabled: true,
        isFunctionReferencesEnabled: true,
        isWasmGCEnabled: true,
        isGCSupportEnabled: true,
        isBulkMemoryEnabled: true,
        isMultiValueEnabled: true,
        isMultiMemoryEnabled: true,
        isMemory64Enabled: true,
        isWideArithmeticEnabled: true,
        areExceptionsEnabled: true,
        areCustomPageSizesEnabled: true,
        strategy: .cranelift,
        craneliftOptimizationLevel: .speedAndSize,
        craneliftRegallocAlgorithm: .singlePass,
        isCraneliftDebugVerifierEnabled: true,
        isCraneliftNaNCanonicalizationEnabled: true,
        profiler: .none,
        memoryMayMove: true,
        signalsBasedTraps: true,
        debugInfo: true,
        parallelCompilation: false,
        nativeUnwindInfo: true,
        usesMachPortsOnMacOS: true,
        usesMemoryInitCopyOnWrite: true,
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
    #expect(options.isSharedMemoryEnabled)
    #expect(options.isTailCallEnabled)
    #expect(options.isReferenceTypesEnabled)
    #expect(options.isFunctionReferencesEnabled)
    #expect(options.isWasmGCEnabled)
    #expect(options.isGCSupportEnabled)
    #expect(options.isBulkMemoryEnabled)
    #expect(options.isMultiValueEnabled)
    #expect(options.isMultiMemoryEnabled)
    #expect(options.isMemory64Enabled)
    #expect(options.isWideArithmeticEnabled)
    #expect(options.areExceptionsEnabled)
    #expect(options.areCustomPageSizesEnabled)
    #expect(options.craneliftRegallocAlgorithm == .singlePass)
    #expect(options.isCraneliftDebugVerifierEnabled)
    #expect(options.isCraneliftNaNCanonicalizationEnabled)
    #expect(options.profiler == .none)
    #expect(options.nativeUnwindInfo)
    #expect(options.usesMachPortsOnMacOS)
    #expect(options.usesMemoryInitCopyOnWrite)

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
