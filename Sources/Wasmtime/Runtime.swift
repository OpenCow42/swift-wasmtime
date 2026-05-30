import Foundation
@preconcurrency import CWasmtime

#if os(Linux)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Sendable handle for an instance stored inside `WasmtimeRuntime`.
public struct RuntimeInstanceID: Sendable, Hashable, CustomStringConvertible {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public var description: String {
        "runtime instance \(rawValue)"
    }
}

/// Sendable handle for a component instance stored inside `WasmtimeRuntime`.
public struct RuntimeComponentInstanceID: Sendable, Hashable, CustomStringConvertible {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public var description: String {
        "runtime component instance \(rawValue)"
    }
}

/// Sendable snapshot of a table element read through `WasmtimeRuntime`.
///
/// Low-level non-null `funcref` values are store-bound `Func` handles. The
/// runtime actor keeps those handles isolated and returns this value snapshot
/// instead.
public enum RuntimeTableElement: Sendable, Equatable, CustomStringConvertible {
    case nullFunctionReference
    case functionReference
    case nullExternalReference

    init(_ element: TableElement) {
        switch element {
        case .nullFunctionReference:
            self = .nullFunctionReference
        case .function:
            self = .functionReference
        case .nullExternalReference:
            self = .nullExternalReference
        }
    }

    public var description: String {
        switch self {
        case .nullFunctionReference:
            "null funcref"
        case .functionReference:
            "funcref"
        case .nullExternalReference:
            "null externref"
        }
    }
}

/// Actor-serialized runtime surface for Swift concurrency.
///
/// `WasmtimeRuntime` keeps non-`Sendable` Wasmtime store-bound handles inside
/// the actor and exposes sendable identifiers and value types to callers.
public actor WasmtimeRuntime {
    private let engine: Engine
    private let store: Store
    private var nextInstanceID = 0
    private var instances: [RuntimeInstanceID: Instance] = [:]
    private var nextComponentInstanceID = 0
    private var componentInstances: [RuntimeComponentInstanceID: ComponentInstance] = [:]

    public init(options: EngineOptions = EngineOptions(), resourceLimits: ResourceLimits? = nil) throws {
        let engine = try Engine(options: options)
        self.engine = engine
        self.store = try Store(engine: engine)
        if let resourceLimits {
            store.setResourceLimits(resourceLimits)
        }
    }

    public init(engine: Engine, resourceLimits: ResourceLimits? = nil) throws {
        self.engine = engine
        self.store = try Store(engine: engine)
        if let resourceLimits {
            store.setResourceLimits(resourceLimits)
        }
    }

    public func compileModule(wat: String) throws -> Module {
        try Module(engine: engine, wat: wat)
    }

    public func compileModule(wasm: [UInt8]) throws -> Module {
        try Module(engine: engine, wasm: wasm)
    }

    public func compileModule(data: Data) throws -> Module {
        try Module(engine: engine, data: data)
    }

    public func compileComponent(wat: String) throws -> Component {
        try Component(engine: engine, wat: wat)
    }

    public func compileComponent(wasm: [UInt8]) throws -> Component {
        try Component(engine: engine, wasm: wasm)
    }

    public func compileComponent(data: Data) throws -> Component {
        try Component(engine: engine, data: data)
    }

    public func setWasi(_ options: WasiOptions = WasiOptions()) throws {
        try store.setWasi(options.makeConfig())
    }

    public func setWasiHTTP() {
        store.setWasiHTTP()
    }

    public func setResourceLimits(_ limits: ResourceLimits) {
        store.setResourceLimits(limits)
    }

    public func collectGarbage() throws {
        try store.collectGarbage()
    }

    public func setFuel(_ fuel: UInt64) throws {
        try store.setFuel(fuel)
    }

    public func fuel() throws -> UInt64 {
        try store.fuel()
    }

    public func setEpochDeadline(ticksBeyondCurrent: UInt64) {
        store.setEpochDeadline(ticksBeyondCurrent: ticksBeyondCurrent)
    }

    public func setEpochDeadlineCallback(_ callback: @escaping EpochDeadlineHandler) {
        store.setEpochDeadlineCallback(callback)
    }

    public func incrementEpoch() {
        engine.incrementEpoch()
    }

    public func instantiate(_ module: Module) throws -> RuntimeInstanceID {
        let instance = try Instance(store: store, module: module)
        let id = RuntimeInstanceID(rawValue: nextInstanceID)
        nextInstanceID += 1
        instances[id] = instance
        return id
    }

    public func instantiate(wat: String) throws -> RuntimeInstanceID {
        try instantiate(compileModule(wat: wat))
    }

    public func instantiate(wasm: [UInt8]) throws -> RuntimeInstanceID {
        try instantiate(compileModule(wasm: wasm))
    }

    public func instantiate(data: Data) throws -> RuntimeInstanceID {
        try instantiate(compileModule(data: data))
    }

    public func instantiateWithLinker(
        _ module: Module,
        allowsShadowing: Bool = false,
        defineWasi: Bool = false,
        defineUnknownImportsAsTraps: Bool = false,
        defineUnknownImportsAsDefaultValues: Bool = false,
        hostFunctions: [RuntimeHostFunction] = []
    ) throws -> RuntimeInstanceID {
        let linker = try Linker(engine: engine)
        linker.allowsShadowing = allowsShadowing
        if defineWasi {
            try linker.defineWasi()
        }
        if defineUnknownImportsAsTraps {
            try linker.defineUnknownImportsAsTraps(module: module)
        }
        if defineUnknownImportsAsDefaultValues {
            try linker.defineUnknownImportsAsDefaultValues(store: store, module: module)
        }
        for function in hostFunctions {
            try linker.defineFunction(module: function.module, name: function.name, type: function.type) { _, arguments in
                try function.body(arguments)
            }
        }
        let instance = try linker.instantiate(store: store, module: module)
        let id = RuntimeInstanceID(rawValue: nextInstanceID)
        nextInstanceID += 1
        instances[id] = instance
        return id
    }

    public func instantiateComponent(
        _ component: Component,
        allowsShadowing: Bool = false,
        addWasiP2: Bool = false,
        addWasiHTTP: Bool = false
    ) throws -> RuntimeComponentInstanceID {
        let linker = try ComponentLinker(engine: engine)
        linker.allowsShadowing = allowsShadowing
        if addWasiP2 {
            try linker.addWasiP2()
        }
        if addWasiHTTP {
            try linker.addWasiHTTP()
        }
        let instance = try linker.instantiate(store: store, component: component)
        let id = RuntimeComponentInstanceID(rawValue: nextComponentInstanceID)
        nextComponentInstanceID += 1
        componentInstances[id] = instance
        return id
    }

    public func call(
        _ functionName: String,
        in instanceID: RuntimeInstanceID,
        arguments: [Value] = []
    ) throws -> [Value] {
        let instance = try instance(for: instanceID)
        return try instance.exportedFunction(named: functionName).call(arguments)
    }

    public func exportKind(named name: String, in instanceID: RuntimeInstanceID) throws -> ExternKind {
        let instance = try instance(for: instanceID)
        return try instance.export(named: name).kind
    }

    public func globalType(named globalName: String, in instanceID: RuntimeInstanceID) throws -> GlobalType {
        let instance = try instance(for: instanceID)
        return try instance.exportedGlobal(named: globalName).type()
    }

    public func globalValue(named globalName: String, in instanceID: RuntimeInstanceID) throws -> Value {
        let instance = try instance(for: instanceID)
        return try instance.exportedGlobal(named: globalName).get()
    }

    public func setGlobal(named globalName: String, in instanceID: RuntimeInstanceID, to value: Value) throws {
        let instance = try instance(for: instanceID)
        try instance.exportedGlobal(named: globalName).set(value)
    }

    public func tableType(named tableName: String = "table", in instanceID: RuntimeInstanceID) throws -> TableType {
        let instance = try instance(for: instanceID)
        return try instance.exportedTable(named: tableName).type()
    }

    public func tableSize(named tableName: String = "table", in instanceID: RuntimeInstanceID) throws -> UInt64 {
        let instance = try instance(for: instanceID)
        return try instance.exportedTable(named: tableName).size
    }

    public func tableElement(
        named tableName: String = "table",
        in instanceID: RuntimeInstanceID,
        index: UInt64
    ) throws -> RuntimeTableElement? {
        let instance = try instance(for: instanceID)
        return try instance.exportedTable(named: tableName).get(index: index).map(RuntimeTableElement.init)
    }

    public func setTableElementToNull(
        named tableName: String = "table",
        in instanceID: RuntimeInstanceID,
        index: UInt64
    ) throws {
        let instance = try instance(for: instanceID)
        let table = try instance.exportedTable(named: tableName)
        try table.set(index: index, to: TableElement.null(for: try table.type().element))
    }

    public func setTableElement(
        named tableName: String = "table",
        in instanceID: RuntimeInstanceID,
        index: UInt64,
        toFunction functionName: String
    ) throws {
        let instance = try instance(for: instanceID)
        let function = try instance.exportedFunction(named: functionName)
        try instance.exportedTable(named: tableName).set(index: index, to: .function(function))
    }

    public func growTable(
        named tableName: String = "table",
        in instanceID: RuntimeInstanceID,
        by deltaElements: UInt64
    ) throws -> UInt64 {
        let instance = try instance(for: instanceID)
        return try instance.exportedTable(named: tableName).grow(by: deltaElements)
    }

    public func readMemory(
        named memoryName: String = "memory",
        in instanceID: RuntimeInstanceID,
        offset: Int,
        length: Int
    ) throws -> [UInt8] {
        let instance = try instance(for: instanceID)
        return try instance.exportedMemory(named: memoryName).read(offset: offset, length: length)
    }

    public func writeMemory(
        named memoryName: String = "memory",
        in instanceID: RuntimeInstanceID,
        offset: Int,
        bytes: [UInt8]
    ) throws {
        let instance = try instance(for: instanceID)
        try instance.exportedMemory(named: memoryName).write(offset: offset, bytes: bytes)
    }

    public func growMemory(
        named memoryName: String = "memory",
        in instanceID: RuntimeInstanceID,
        by deltaPages: UInt64
    ) throws -> UInt64 {
        let instance = try instance(for: instanceID)
        return try instance.exportedMemory(named: memoryName).grow(by: deltaPages)
    }

    public func memorySize(named memoryName: String = "memory", in instanceID: RuntimeInstanceID) throws -> UInt64 {
        let instance = try instance(for: instanceID)
        return try instance.exportedMemory(named: memoryName).size
    }

    public func memoryDataSize(named memoryName: String = "memory", in instanceID: RuntimeInstanceID) throws -> Int {
        let instance = try instance(for: instanceID)
        return try instance.exportedMemory(named: memoryName).dataSize
    }

    public func call(_ functionName: String, in componentInstanceID: RuntimeComponentInstanceID) throws {
        guard let instance = componentInstances[componentInstanceID] else {
            throw WasmtimeError.missingRuntimeComponentInstance(componentInstanceID)
        }
        try instance.exportedFunction(named: functionName).call()
    }

    private func instance(for instanceID: RuntimeInstanceID) throws -> Instance {
        guard let instance = instances[instanceID] else {
            throw WasmtimeError.missingRuntimeInstance(instanceID)
        }
        return instance
    }
}
