import Foundation
import Testing
@preconcurrency import CWasmtime
@testable import Wasmtime

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

@Test func v128GlobalsCanBeCreatedReadAndSetFromSwift() throws {
    let config = try Config()
    config.isSIMDEnabled = true
    let engine = try Engine(config: config)
    let store = try Store(engine: engine)
    let first = V128(i32x4: SIMD4<Int32>(1, 2, 3, 4))
    let second = V128(f32x4: SIMD4<Float>(1.25, 2.5, 3.75, 4.5))
    let global = try Global(store: store, type: GlobalType(content: .v128, isMutable: true), value: .v128(first))

    let globalType = try global.type()
    #expect(globalType.content == .v128)
    #expect(globalType.isMutable)
    #expect(try global.get() == .v128(first))

    try global.set(.v128(second))
    #expect(try global.get() == .v128(second))

    let module = try Module(
        engine: engine,
        wat: """
        (module
          (global (export "vector") v128 (v128.const i32x4 5 6 7 8)))
        """
    )
    let instance = try Instance(store: store, module: module)
    #expect(try instance.exportedGlobal(named: "vector").type().content == .v128)
    #expect(try instance.exportedGlobal(named: "vector").get() == .v128(V128(i32x4: SIMD4<Int32>(5, 6, 7, 8))))
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
