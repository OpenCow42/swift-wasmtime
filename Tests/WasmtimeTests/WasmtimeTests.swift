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
    acceptsSendable(Value.i32(1))
    acceptsSendable(WasiDirectoryPermissions.read)
    acceptsSendable(WasiFilePermissions.read)
    acceptsSendable(RuntimeInstanceID(rawValue: 1))
    acceptsSendable(Trap(message: "trap", code: nil))
    acceptsSendable(WasmtimeError.missingExport("missing"))
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
    #expect(WasmtimeError.api(message: "bad", exitStatus: 2).description == "bad (WASI exit status 2)")
    #expect(WasmtimeError.api(message: "bad", exitStatus: nil).description == "bad")
    #expect(WasmtimeError.unsupportedValueKind(99).description == "unsupported Wasmtime value kind: 99")
    #expect(WasmtimeError.wrongExportKind(name: "x", expected: "func", actual: "global").description == "export x is global, expected func")
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
