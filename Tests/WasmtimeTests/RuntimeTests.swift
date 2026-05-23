import Foundation
import Testing
@preconcurrency import CWasmtime
@testable import Wasmtime

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

@Test func runtimeActorManagesExportedGlobalsAndTables() async throws {
    let runtime = try WasmtimeRuntime()
    let instance = try await runtime.instantiate(
        wat: """
        (module
          (global (export "counter") (mut i32) (i32.const 4))
          (global (export "answer") i64 (i64.const 42))
          (table (export "table") 2 4 funcref)
          (table (export "externs") 1 2 externref)
          (func (export "answer_func") (result i32)
            i32.const 42)
          (func (export "read_counter") (result i32)
            global.get 0)
          (memory (export "memory") 1)
          (func (export "not-global")))
        """
    )

    let counterType = try await runtime.globalType(named: "counter", in: instance)
    #expect(counterType.content == .i32)
    #expect(counterType.isMutable)
    #expect(try await runtime.globalValue(named: "counter", in: instance) == .i32(4))

    try await runtime.setGlobal(named: "counter", in: instance, to: .i32(9))
    #expect(try await runtime.globalValue(named: "counter", in: instance) == .i32(9))
    #expect(try await runtime.call("read_counter", in: instance) == [.i32(9)])

    let answerType = try await runtime.globalType(named: "answer", in: instance)
    #expect(answerType.content == .i64)
    #expect(!answerType.isMutable)
    #expect(try await runtime.globalValue(named: "answer", in: instance) == .i64(42))

    do {
        try await runtime.setGlobal(named: "answer", in: instance, to: .i64(7))
        Issue.record("expected immutable global set to fail")
    } catch is WasmtimeError {
    }
    do {
        _ = try await runtime.globalValue(named: "not-global", in: instance)
        Issue.record("expected wrong export kind")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("expected global"))
    }
    do {
        _ = try await runtime.globalValue(named: "counter", in: RuntimeInstanceID(rawValue: 999))
        Issue.record("expected missing runtime instance")
    } catch let error as WasmtimeError {
        #expect(error == .missingRuntimeInstance(RuntimeInstanceID(rawValue: 999)))
    }

    let tableType = try await runtime.tableType(in: instance)
    #expect(tableType.element == .functionReference)
    #expect(tableType.minimumElements == 2)
    #expect(tableType.maximumElements == 4)
    #expect(try await runtime.tableSize(in: instance) == 2)
    #expect(try await runtime.tableElement(in: instance, index: 0) == .nullFunctionReference)
    #expect(try await runtime.tableElement(in: instance, index: 9) == nil)

    try await runtime.setTableElement(in: instance, index: 0, toFunction: "answer_func")
    #expect(try await runtime.tableElement(in: instance, index: 0) == .functionReference)
    try await runtime.setTableElementToNull(in: instance, index: 0)
    #expect(try await runtime.tableElement(in: instance, index: 0) == .nullFunctionReference)
    #expect(try await runtime.growTable(in: instance, by: 1) == 2)
    #expect(try await runtime.tableSize(in: instance) == 3)
    #expect(try await runtime.tableElement(in: instance, index: 2) == .nullFunctionReference)

    let externsType = try await runtime.tableType(named: "externs", in: instance)
    #expect(externsType.element == .externalReference)
    #expect(try await runtime.tableSize(named: "externs", in: instance) == 1)
    #expect(try await runtime.tableElement(named: "externs", in: instance, index: 0) == .nullExternalReference)
    try await runtime.setTableElementToNull(named: "externs", in: instance, index: 0)
    #expect(try await runtime.growTable(named: "externs", in: instance, by: 1) == 1)
    #expect(try await runtime.tableSize(named: "externs", in: instance) == 2)

    #expect(RuntimeTableElement.nullFunctionReference.description == "null funcref")
    #expect(RuntimeTableElement.functionReference.description == "funcref")
    #expect(RuntimeTableElement.nullExternalReference.description == "null externref")

    do {
        _ = try await runtime.tableSize(named: "memory", in: instance)
        Issue.record("expected wrong export kind")
    } catch let error as WasmtimeError {
        #expect(error.description.contains("expected table"))
    }
    do {
        _ = try await runtime.tableSize(named: "missing", in: instance)
        Issue.record("expected missing table export")
    } catch let error as WasmtimeError {
        #expect(error == .missingExport("missing"))
    }
    do {
        try await runtime.setTableElement(in: instance, index: 0, toFunction: "missing")
        Issue.record("expected missing function export")
    } catch let error as WasmtimeError {
        #expect(error == .missingExport("missing"))
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
