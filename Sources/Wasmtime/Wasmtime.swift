import Foundation
@preconcurrency import CWasmtime

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

public final class Config {
    private var raw: OpaquePointer?

    public init() throws {
        guard let raw = wasm_config_new() else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasm_config_new returned nil")
        }
        self.raw = raw
    }

    public var isComponentModelEnabled: Bool = false {
        didSet {
            wasmtime_config_wasm_component_model_set(requiredRaw, isComponentModelEnabled)
        }
    }

    public var isSIMDEnabled: Bool = false {
        didSet {
            wasmtime_config_wasm_simd_set(requiredRaw, isSIMDEnabled)
        }
    }

    public var isRelaxedSIMDEnabled: Bool = false {
        didSet {
            wasmtime_config_wasm_relaxed_simd_set(requiredRaw, isRelaxedSIMDEnabled)
        }
    }

    public var isRelaxedSIMDDeterministic: Bool = false {
        didSet {
            wasmtime_config_wasm_relaxed_simd_deterministic_set(requiredRaw, isRelaxedSIMDDeterministic)
        }
    }

    public var strategy: CompilationStrategy = .automatic {
        didSet {
            wasmtime_config_strategy_set(requiredRaw, strategy.rawValue)
        }
    }

    public var craneliftOptimizationLevel: CraneliftOptimizationLevel = .speed {
        didSet {
            wasmtime_config_cranelift_opt_level_set(requiredRaw, craneliftOptimizationLevel.rawValue)
        }
    }

    public var memoryMayMove: Bool = false {
        didSet {
            wasmtime_config_memory_may_move_set(requiredRaw, memoryMayMove)
        }
    }

    public var signalsBasedTraps: Bool = true {
        didSet {
            wasmtime_config_signals_based_traps_set(requiredRaw, signalsBasedTraps)
        }
    }

    public var debugInfo: Bool = false {
        didSet {
            wasmtime_config_debug_info_set(requiredRaw, debugInfo)
        }
    }

    public var parallelCompilation: Bool = true {
        didSet {
            wasmtime_config_parallel_compilation_set(requiredRaw, parallelCompilation)
        }
    }

    public func setTarget(_ target: String) throws {
        try target.withCString { cTarget in
            try WasmtimeError.throwIfNeeded(wasmtime_config_target_set(requiredRaw, cTarget))
        }
    }

    public func enableCraneliftFlag(_ flag: String) {
        flag.withCString { cFlag in
            wasmtime_config_cranelift_flag_enable(requiredRaw, cFlag)
        }
    }

    public func setCraneliftFlag(_ flag: String, to value: String) {
        flag.withCString { cFlag in
            value.withCString { cValue in
                wasmtime_config_cranelift_flag_set(requiredRaw, cFlag, cValue)
            }
        }
    }

    public func setMemoryReservation(_ bytes: UInt64) {
        wasmtime_config_memory_reservation_set(requiredRaw, bytes)
    }

    public func setMemoryGuardSize(_ bytes: UInt64) {
        wasmtime_config_memory_guard_size_set(requiredRaw, bytes)
    }

    public func setMemoryReservationForGrowth(_ bytes: UInt64) {
        wasmtime_config_memory_reservation_for_growth_set(requiredRaw, bytes)
    }

    func release() -> OpaquePointer {
        let current = requiredRaw
        raw = nil
        return current
    }

    private var requiredRaw: OpaquePointer {
        guard let raw else { // coverage:ignore programmer-error precondition
            preconditionFailure("Config has already been consumed by Engine.init(config:)") // coverage:ignore crash branch
        }
        return raw
    }

    deinit {
        if let raw {
            wasm_config_delete(raw)
        }
    }

    func apply(_ options: EngineOptions) throws {
        isComponentModelEnabled = options.isComponentModelEnabled
        isSIMDEnabled = options.isSIMDEnabled
        isRelaxedSIMDEnabled = options.isRelaxedSIMDEnabled
        isRelaxedSIMDDeterministic = options.isRelaxedSIMDDeterministic
        strategy = options.strategy
        craneliftOptimizationLevel = options.craneliftOptimizationLevel
        memoryMayMove = options.memoryMayMove
        signalsBasedTraps = options.signalsBasedTraps
        debugInfo = options.debugInfo
        parallelCompilation = options.parallelCompilation

        if let target = options.target {
            try setTarget(target)
        }
        for flag in options.enabledCraneliftFlags {
            enableCraneliftFlag(flag)
        }
        for (flag, value) in options.craneliftFlagValues.sorted(by: { $0.key < $1.key }) {
            setCraneliftFlag(flag, to: value)
        }
        if let memoryReservation = options.memoryReservation {
            setMemoryReservation(memoryReservation)
        }
        if let memoryGuardSize = options.memoryGuardSize {
            setMemoryGuardSize(memoryGuardSize)
        }
        if let memoryReservationForGrowth = options.memoryReservationForGrowth {
            setMemoryReservationForGrowth(memoryReservationForGrowth)
        }
    }
}

public struct EngineOptions: Sendable, Equatable {
    public var isComponentModelEnabled: Bool
    public var isSIMDEnabled: Bool
    public var isRelaxedSIMDEnabled: Bool
    public var isRelaxedSIMDDeterministic: Bool
    public var strategy: CompilationStrategy
    public var craneliftOptimizationLevel: CraneliftOptimizationLevel
    public var memoryMayMove: Bool
    public var signalsBasedTraps: Bool
    public var debugInfo: Bool
    public var parallelCompilation: Bool
    public var target: String?
    public var enabledCraneliftFlags: [String]
    public var craneliftFlagValues: [String: String]
    public var memoryReservation: UInt64?
    public var memoryGuardSize: UInt64?
    public var memoryReservationForGrowth: UInt64?

    public init(
        isComponentModelEnabled: Bool = false,
        isSIMDEnabled: Bool = false,
        isRelaxedSIMDEnabled: Bool = false,
        isRelaxedSIMDDeterministic: Bool = false,
        strategy: CompilationStrategy = .automatic,
        craneliftOptimizationLevel: CraneliftOptimizationLevel = .speed,
        memoryMayMove: Bool = false,
        signalsBasedTraps: Bool = true,
        debugInfo: Bool = false,
        parallelCompilation: Bool = true,
        target: String? = nil,
        enabledCraneliftFlags: [String] = [],
        craneliftFlagValues: [String: String] = [:],
        memoryReservation: UInt64? = nil,
        memoryGuardSize: UInt64? = nil,
        memoryReservationForGrowth: UInt64? = nil
    ) {
        self.isComponentModelEnabled = isComponentModelEnabled
        self.isSIMDEnabled = isSIMDEnabled
        self.isRelaxedSIMDEnabled = isRelaxedSIMDEnabled
        self.isRelaxedSIMDDeterministic = isRelaxedSIMDDeterministic
        self.strategy = strategy
        self.craneliftOptimizationLevel = craneliftOptimizationLevel
        self.memoryMayMove = memoryMayMove
        self.signalsBasedTraps = signalsBasedTraps
        self.debugInfo = debugInfo
        self.parallelCompilation = parallelCompilation
        self.target = target
        self.enabledCraneliftFlags = enabledCraneliftFlags
        self.craneliftFlagValues = craneliftFlagValues
        self.memoryReservation = memoryReservation
        self.memoryGuardSize = memoryGuardSize
        self.memoryReservationForGrowth = memoryReservationForGrowth
    }

    public mutating func enableCraneliftFlag(_ flag: String) {
        enabledCraneliftFlags.append(flag)
    }

    public mutating func setCraneliftFlag(_ flag: String, to value: String) {
        craneliftFlagValues[flag] = value
    }

    public mutating func setMemoryReservation(_ bytes: UInt64) {
        memoryReservation = bytes
    }

    public mutating func setMemoryGuardSize(_ bytes: UInt64) {
        memoryGuardSize = bytes
    }

    public mutating func setMemoryReservationForGrowth(_ bytes: UInt64) {
        memoryReservationForGrowth = bytes
    }
}

public enum CompilationStrategy: Sendable, Equatable {
    case automatic
    case cranelift

    var rawValue: wasmtime_strategy_t {
        switch self {
        case .automatic: wasmtime_strategy_t(WASMTIME_STRATEGY_AUTO.rawValue)
        case .cranelift: wasmtime_strategy_t(WASMTIME_STRATEGY_CRANELIFT.rawValue)
        }
    }
}

public enum CraneliftOptimizationLevel: Sendable, Equatable {
    case none
    case speed
    case speedAndSize

    var rawValue: wasmtime_opt_level_t {
        switch self {
        case .none: wasmtime_opt_level_t(WASMTIME_OPT_LEVEL_NONE.rawValue)
        case .speed: wasmtime_opt_level_t(WASMTIME_OPT_LEVEL_SPEED.rawValue)
        case .speedAndSize: wasmtime_opt_level_t(WASMTIME_OPT_LEVEL_SPEED_AND_SIZE.rawValue)
        }
    }
}

public final class Engine: @unchecked Sendable {
    let raw: OpaquePointer

    public init() throws {
        guard let raw = wasm_engine_new() else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasm_engine_new returned nil")
        }
        self.raw = raw
    }

    public init(config: Config) throws {
        guard let raw = wasm_engine_new_with_config(config.release()) else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasm_engine_new_with_config returned nil")
        }
        self.raw = raw
    }

    public convenience init(options: EngineOptions) throws {
        let config = try Config()
        try config.apply(options)
        try self.init(config: config)
    }

    deinit {
        wasm_engine_delete(raw)
    }
}

public final class Store {
    private let engine: Engine
    let raw: OpaquePointer
    var context: OpaquePointer {
        wasmtime_store_context(raw)
    }

    public init(engine: Engine) throws {
        guard let raw = wasmtime_store_new(engine.raw, nil, nil) else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasmtime_store_new returned nil")
        }
        self.engine = engine
        self.raw = raw
    }

    public func setWasi(_ config: WasiConfig) throws {
        try WasmtimeError.throwIfNeeded(wasmtime_context_set_wasi(context, config.release()))
    }

    public func setWasiHTTP() {
        wasmtime_context_set_wasi_http(context)
    }

    deinit {
        wasmtime_store_delete(raw)
    }
}

public final class Module: @unchecked Sendable {
    private let engine: Engine
    let raw: OpaquePointer

    public convenience init(engine: Engine, wasm: [UInt8]) throws {
        try self.init(engine: engine, bytes: wasm)
    }

    public convenience init(engine: Engine, data: Data) throws {
        try self.init(engine: engine, bytes: Array(data))
    }

    public convenience init(engine: Engine, wat: String) throws {
        try self.init(engine: engine, bytes: WasmText.compile(wat))
    }

    private init(engine: Engine, bytes: [UInt8]) throws {
        var module: OpaquePointer?
        let error = bytes.withUnsafeBufferPointer { buffer in
            wasmtime_module_new(engine.raw, buffer.baseAddress, buffer.count, &module)
        }
        try WasmtimeError.throwIfNeeded(error)
        guard let module else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasmtime_module_new returned nil without an error")
        }
        self.engine = engine
        self.raw = module
    }

    deinit {
        wasmtime_module_delete(raw)
    }
}

public final class Component: @unchecked Sendable {
    private let engine: Engine
    let raw: OpaquePointer

    public convenience init(engine: Engine, wasm: [UInt8]) throws {
        try self.init(engine: engine, bytes: wasm)
    }

    public convenience init(engine: Engine, data: Data) throws {
        try self.init(engine: engine, bytes: Array(data))
    }

    public convenience init(engine: Engine, wat: String) throws {
        try self.init(engine: engine, bytes: WasmText.compile(wat))
    }

    private init(engine: Engine, bytes: [UInt8]) throws {
        var component: OpaquePointer?
        let error = bytes.withUnsafeBufferPointer { buffer in
            wasmtime_component_new(engine.raw, buffer.baseAddress, buffer.count, &component)
        }
        try WasmtimeError.throwIfNeeded(error)
        guard let component else { // coverage:ignore defensive C invariant
            throw WasmtimeError.allocationFailed("wasmtime_component_new returned nil without an error")
        }
        self.engine = engine
        self.raw = component
    }

    deinit {
        wasmtime_component_delete(raw)
    }
}

public final class Instance {
    private let store: Store
    let raw: wasmtime_instance_t

    public init(store: Store, module: Module) throws {
        var instance = wasmtime_instance_t()
        var trap: OpaquePointer?
        let error = wasmtime_instance_new(store.context, module.raw, nil, 0, &instance, &trap)
        try WasmtimeError.throwIfNeeded(error, trap: trap)
        self.store = store
        self.raw = instance
    }

    init(store: Store, raw: wasmtime_instance_t) {
        self.store = store
        self.raw = raw
    }

    public func exportedFunction(named name: String) throws -> Func {
        var item = wasmtime_extern_t()
        var instance = raw
        let found = name.withCString { cName in
            wasmtime_instance_export_get(store.context, &instance, cName, strlen(cName), &item)
        }
        guard found else {
            throw WasmtimeError.missingExport(name)
        }
        defer { wasmtime_extern_delete(&item) }

        guard item.kind == WASMTIME_EXTERN_FUNC else {
            throw WasmtimeError.wrongExportKind(name: name, expected: "func", actual: ExternKind(rawValue: item.kind).description)
        }

        return Func(store: store, raw: item.of.func)
    }
}

public final class Caller {
    private let state: CallerState

    init(raw: OpaquePointer?) {
        self.state = CallerState(raw: raw)
    }

    public func exportKind(named name: String) throws -> ExternKind? {
        guard let raw = try state.currentRaw() else {
            return nil
        }

        var item = wasmtime_extern_t()
        let found = name.withCString { cName in
            wasmtime_caller_export_get(raw, cName, strlen(cName), &item)
        }
        guard found else {
            return nil
        }
        defer { wasmtime_extern_delete(&item) }
        return ExternKind(rawValue: item.kind)
    }

    public func readMemory(named name: String = "memory", offset: Int, length: Int) throws -> [UInt8]? {
        guard offset >= 0, length >= 0 else {
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: length, memorySize: 0)
        }
        guard let raw = try state.currentRaw(), var memory = exportedMemory(named: name, caller: raw) else {
            return nil
        }
        let context = wasmtime_caller_context(raw)
        let memorySize = wasmtime_memory_data_size(context, &memory)
        guard offset <= memorySize, length <= memorySize - offset else {
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: length, memorySize: memorySize)
        }
        guard let data = wasmtime_memory_data(context, &memory) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: length, memorySize: memorySize)
        }
        return Array(UnsafeBufferPointer(start: data.advanced(by: offset), count: length))
    }

    public func writeMemory(named name: String = "memory", offset: Int, bytes: [UInt8]) throws -> Bool {
        guard offset >= 0 else {
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: bytes.count, memorySize: 0)
        }
        guard let raw = try state.currentRaw(), var memory = exportedMemory(named: name, caller: raw) else {
            return false
        }
        let context = wasmtime_caller_context(raw)
        let memorySize = wasmtime_memory_data_size(context, &memory)
        guard offset <= memorySize, bytes.count <= memorySize - offset else {
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: bytes.count, memorySize: memorySize)
        }
        guard let data = wasmtime_memory_data(context, &memory) else { // coverage:ignore defensive C invariant
            throw WasmtimeError.memoryAccessOutOfBounds(offset: offset, length: bytes.count, memorySize: memorySize)
        }
        bytes.withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                data.advanced(by: offset).update(from: baseAddress, count: buffer.count)
            }
        }
        return true
    }

    private func exportedMemory(named name: String, caller: OpaquePointer) -> wasmtime_memory_t? {
        var item = wasmtime_extern_t()
        let found = name.withCString { cName in
            wasmtime_caller_export_get(caller, cName, strlen(cName), &item)
        }
        guard found else {
            return nil
        }
        defer { wasmtime_extern_delete(&item) }
        guard item.kind == WASMTIME_EXTERN_MEMORY else { // coverage:ignore wasmtime_caller_export_get currently returns only memories
            return nil // coverage:ignore wasmtime_caller_export_get currently returns only memories
        }
        return item.of.memory
    }

    func invalidate() {
        state.invalidate()
    }
}

public final class ComponentInstance {
    private let store: Store
    let raw: wasmtime_component_instance_t

    init(store: Store, raw: wasmtime_component_instance_t) {
        self.store = store
        self.raw = raw
    }

    public func exportedFunction(named name: String) throws -> ComponentFunction {
        var instance = raw
        let exportIndex = name.withCString { cName in
            wasmtime_component_instance_get_export_index(&instance, store.context, nil, cName, strlen(cName))
        }
        guard let exportIndex else {
            throw WasmtimeError.missingExport(name)
        }
        defer { wasmtime_component_export_index_delete(exportIndex) }

        var function = wasmtime_component_func_t()
        guard wasmtime_component_instance_get_func(&instance, store.context, exportIndex, &function) else {
            throw WasmtimeError.wrongExportKind(name: name, expected: "func", actual: "component export")
        }

        return ComponentFunction(store: store, raw: function)
    }
}

public final class Linker {
    private let engine: Engine
    let raw: OpaquePointer

    public init(engine: Engine) throws {
        guard let raw = wasmtime_linker_new(engine.raw) else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasmtime_linker_new returned nil")
        }
        self.engine = engine
        self.raw = raw
    }

    public var allowsShadowing: Bool = false {
        didSet {
            wasmtime_linker_allow_shadowing(raw, allowsShadowing)
        }
    }

    public func defineWasi() throws {
        try WasmtimeError.throwIfNeeded(wasmtime_linker_define_wasi(raw))
    }

    public func defineUnknownImportsAsTraps(module: Module) throws {
        try WasmtimeError.throwIfNeeded(wasmtime_linker_define_unknown_imports_as_traps(raw, module.raw))
    }

    public func defineUnknownImportsAsDefaultValues(store: Store, module: Module) throws {
        try WasmtimeError.throwIfNeeded(wasmtime_linker_define_unknown_imports_as_default_values(raw, store.context, module.raw))
    }

    public func defineInstance(store: Store, name: String, instance: Instance) throws {
        var instance = instance.raw
        try name.withCString { cName in
            try WasmtimeError.throwIfNeeded(
                wasmtime_linker_define_instance(raw, store.context, cName, strlen(cName), &instance)
            )
        }
    }

    public func defineModule(store: Store, name: String, module: Module) throws {
        try name.withCString { cName in
            try WasmtimeError.throwIfNeeded(
                wasmtime_linker_module(raw, store.context, cName, strlen(cName), module.raw)
            )
        }
    }

    public func define(module: String, name: String, function: Func) throws {
        var item = wasmtime_extern_t()
        item.kind = wasmtime_extern_kind_t(WASMTIME_EXTERN_FUNC)
        item.of.func = function.raw
        try module.withCString { cModule in
            try name.withCString { cName in
                try WasmtimeError.throwIfNeeded(
                    wasmtime_linker_define(raw, function.store.context, cModule, strlen(cModule), cName, strlen(cName), &item)
                )
            }
        }
    }

    public func defineFunction(
        module: String,
        name: String,
        type: FunctionType,
        _ body: @escaping HostFunction
    ) throws {
        let rawType = try type.makeRaw()
        defer { wasm_functype_delete(rawType) }
        let box = HostFunctionBox(type: type, body: body)
        let data = Unmanaged.passRetained(box).toOpaque()
        let error = module.withCString { cModule in
            name.withCString { cName in
                wasmtime_linker_define_func(
                    raw,
                    cModule,
                    strlen(cModule),
                    cName,
                    strlen(cName),
                    rawType,
                    hostFunctionCallback,
                    data,
                    hostFunctionFinalizer
                )
            }
        }
        if let error {
            throw WasmtimeError.fromOwned(error)
        }
    }

    public func defineFunction(
        module: String,
        name: String,
        parameters: [ValueKind] = [],
        results: [ValueKind] = [],
        _ body: @escaping HostFunction
    ) throws {
        try defineFunction(
            module: module,
            name: name,
            type: FunctionType(parameters: parameters, results: results),
            body
        )
    }

    public func instantiate(store: Store, module: Module) throws -> Instance {
        var instance = wasmtime_instance_t()
        var trap: OpaquePointer?
        let error = wasmtime_linker_instantiate(raw, store.context, module.raw, &instance, &trap)
        try WasmtimeError.throwIfNeeded(error, trap: trap)
        return Instance(store: store, raw: instance)
    }

    deinit {
        wasmtime_linker_delete(raw)
    }
}

public final class ComponentLinker {
    private let engine: Engine
    let raw: OpaquePointer

    public init(engine: Engine) throws {
        guard let raw = wasmtime_component_linker_new(engine.raw) else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasmtime_component_linker_new returned nil")
        }
        self.engine = engine
        self.raw = raw
    }

    public var allowsShadowing: Bool = false {
        didSet {
            wasmtime_component_linker_allow_shadowing(raw, allowsShadowing)
        }
    }

    public func addWasiP2() throws {
        try WasmtimeError.throwIfNeeded(wasmtime_component_linker_add_wasip2(raw))
    }

    public func addWasiHTTP() throws {
        try WasmtimeError.throwIfNeeded(wasmtime_component_linker_add_wasi_http(raw))
    }

    public func instantiate(store: Store, component: Component) throws -> ComponentInstance {
        var instance = wasmtime_component_instance_t()
        let error = wasmtime_component_linker_instantiate(raw, store.context, component.raw, &instance)
        try WasmtimeError.throwIfNeeded(error)
        return ComponentInstance(store: store, raw: instance)
    }

    deinit {
        wasmtime_component_linker_delete(raw)
    }
}

public final class Func {
    fileprivate let store: Store
    let raw: wasmtime_func_t

    public init(
        store: Store,
        type: FunctionType,
        _ body: @escaping HostFunction
    ) throws {
        let rawType = try type.makeRaw()
        defer { wasm_functype_delete(rawType) }
        let box = HostFunctionBox(type: type, body: body)
        let data = Unmanaged.passRetained(box).toOpaque()
        var function = wasmtime_func_t()
        wasmtime_func_new(
            store.context,
            rawType,
            hostFunctionCallback,
            data,
            hostFunctionFinalizer,
            &function
        )
        self.store = store
        self.raw = function
    }

    public convenience init(
        store: Store,
        parameters: [ValueKind] = [],
        results: [ValueKind] = [],
        _ body: @escaping HostFunction
    ) throws {
        try self.init(store: store, type: FunctionType(parameters: parameters, results: results), body)
    }

    init(store: Store, raw: wasmtime_func_t) {
        self.store = store
        self.raw = raw
    }

    public func call(_ arguments: [Value] = []) throws -> [Value] {
        let resultCount = self.resultCount()
        let rawArguments = arguments.map(\.rawValue)
        var rawResults = Array(repeating: wasmtime_val_t(), count: resultCount)
        var trap: OpaquePointer?
        var function = raw

        let error = rawArguments.withUnsafeBufferPointer { argsBuffer in
            rawResults.withUnsafeMutableBufferPointer { resultsBuffer in
                wasmtime_func_call(
                    store.context,
                    &function,
                    argsBuffer.baseAddress,
                    argsBuffer.count,
                    resultsBuffer.baseAddress,
                    resultsBuffer.count,
                    &trap
                )
            }
        }
        try WasmtimeError.throwIfNeeded(error, trap: trap)
        defer {
            for index in rawResults.indices {
                wasmtime_val_unroot(&rawResults[index])
            }
        }
        return try rawResults.map(Value.init(rawValue:))
    }

    private func resultCount() -> Int {
        var function = raw
        guard let type = wasmtime_func_type(store.context, &function) else { // coverage:ignore defensive C invariant
            return 0
        }
        defer { wasm_functype_delete(type) }
        guard let results = wasm_functype_results(type) else { // coverage:ignore defensive C invariant
            return 0
        }
        return results.pointee.size
    }
}

public final class ComponentFunction {
    private let store: Store
    let raw: wasmtime_component_func_t

    init(store: Store, raw: wasmtime_component_func_t) {
        self.store = store
        self.raw = raw
    }

    public func call() throws {
        var function = raw
        try WasmtimeError.throwIfNeeded(
            wasmtime_component_func_call(&function, store.context, nil, 0, nil, 0)
        )
    }
}

public struct RuntimeInstanceID: Sendable, Hashable, CustomStringConvertible {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public var description: String {
        "runtime instance \(rawValue)"
    }
}

public struct RuntimeComponentInstanceID: Sendable, Hashable, CustomStringConvertible {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public var description: String {
        "runtime component instance \(rawValue)"
    }
}

public actor WasmtimeRuntime {
    private let engine: Engine
    private let store: Store
    private var nextInstanceID = 0
    private var instances: [RuntimeInstanceID: Instance] = [:]
    private var nextComponentInstanceID = 0
    private var componentInstances: [RuntimeComponentInstanceID: ComponentInstance] = [:]

    public init(options: EngineOptions = EngineOptions()) throws {
        let engine = try Engine(options: options)
        self.engine = engine
        self.store = try Store(engine: engine)
    }

    public init(engine: Engine) throws {
        self.engine = engine
        self.store = try Store(engine: engine)
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
        guard let instance = instances[instanceID] else {
            throw WasmtimeError.missingRuntimeInstance(instanceID)
        }
        return try instance.exportedFunction(named: functionName).call(arguments)
    }

    public func call(_ functionName: String, in componentInstanceID: RuntimeComponentInstanceID) throws {
        guard let instance = componentInstances[componentInstanceID] else {
            throw WasmtimeError.missingRuntimeComponentInstance(componentInstanceID)
        }
        try instance.exportedFunction(named: functionName).call()
    }
}

public final class WasiConfig {
    private var raw: OpaquePointer?

    public init() throws {
        guard let raw = wasi_config_new() else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasi_config_new returned nil")
        }
        self.raw = raw
    }

    public func setArguments(_ arguments: [String]) throws {
        try withCStringArray(arguments) { pointers in
            guard wasi_config_set_argv(requiredRaw, pointers.count, pointers.baseAddress) else { // coverage:ignore Swift String UTF-8 is valid
                throw WasmtimeError.wasiConfigurationFailed("WASI argv must contain valid UTF-8")
            }
        }
    }

    public func inheritArguments() {
        wasi_config_inherit_argv(requiredRaw)
    }

    public func setEnvironment(_ environment: [String: String]) throws {
        let entries = environment.sorted { $0.key < $1.key }
        try withCStringArray(entries.map(\.key)) { names in
            try withCStringArray(entries.map(\.value)) { values in
                guard wasi_config_set_env(requiredRaw, names.count, names.baseAddress, values.baseAddress) else { // coverage:ignore Swift String UTF-8 is valid
                    throw WasmtimeError.wasiConfigurationFailed("WASI environment must contain valid UTF-8")
                }
            }
        }
    }

    public func inheritEnvironment() {
        wasi_config_inherit_env(requiredRaw)
    }

    public func inheritStandardInput() {
        wasi_config_inherit_stdin(requiredRaw)
    }

    public func setStandardInputBytes(_ bytes: [UInt8]) {
        var byteVector = wasm_byte_vec_t()
        bytes.withUnsafeBufferPointer { buffer in
            wasm_byte_vec_new(&byteVector, buffer.count, buffer.baseAddress)
        }
        wasi_config_set_stdin_bytes(requiredRaw, &byteVector)
    }

    public func setStandardInputData(_ data: Data) {
        setStandardInputBytes(Array(data))
    }

    public func inheritStandardOutput() {
        wasi_config_inherit_stdout(requiredRaw)
    }

    public func inheritStandardError() {
        wasi_config_inherit_stderr(requiredRaw)
    }

    public func setStandardOutputHandler(_ handler: @escaping WasiOutputHandler) {
        let box = Unmanaged.passRetained(WasiOutputHandlerBox(handler))
        wasi_config_set_stdout_custom(requiredRaw, wasiOutputHandlerCallback, box.toOpaque(), wasiOutputHandlerFinalizer)
    }

    public func setStandardErrorHandler(_ handler: @escaping WasiOutputHandler) {
        let box = Unmanaged.passRetained(WasiOutputHandlerBox(handler))
        wasi_config_set_stderr_custom(requiredRaw, wasiOutputHandlerCallback, box.toOpaque(), wasiOutputHandlerFinalizer)
    }

    public func setStandardInputFile(_ path: String) throws {
        try path.withCString { cPath in
            guard wasi_config_set_stdin_file(requiredRaw, cPath) else {
                throw WasmtimeError.wasiConfigurationFailed("could not open WASI stdin file: \(path)")
            }
        }
    }

    public func setStandardOutputFile(_ path: String) throws {
        try path.withCString { cPath in
            guard wasi_config_set_stdout_file(requiredRaw, cPath) else {
                throw WasmtimeError.wasiConfigurationFailed("could not open WASI stdout file: \(path)")
            }
        }
    }

    public func setStandardErrorFile(_ path: String) throws {
        try path.withCString { cPath in
            guard wasi_config_set_stderr_file(requiredRaw, cPath) else {
                throw WasmtimeError.wasiConfigurationFailed("could not open WASI stderr file: \(path)")
            }
        }
    }

    public func preopenDirectory(
        hostPath: String,
        guestPath: String,
        directoryPermissions: WasiDirectoryPermissions = [.read],
        filePermissions: WasiFilePermissions = [.read]
    ) throws {
        try hostPath.withCString { cHostPath in
            try guestPath.withCString { cGuestPath in
                guard wasi_config_preopen_dir(
                    requiredRaw,
                    cHostPath,
                    cGuestPath,
                    directoryPermissions.rawValue,
                    filePermissions.rawValue
                ) else {
                    throw WasmtimeError.wasiConfigurationFailed(
                        "could not preopen WASI directory: \(hostPath) as \(guestPath)"
                    )
                }
            }
        }
    }

    func release() -> OpaquePointer {
        let current = requiredRaw
        raw = nil
        return current
    }

    private var requiredRaw: OpaquePointer {
        guard let raw else { // coverage:ignore programmer-error precondition
            preconditionFailure("WasiConfig has already been consumed by Store.setWasi(_:)") // coverage:ignore crash branch
        }
        return raw
    }

    deinit {
        if let raw {
            wasi_config_delete(raw)
        }
    }
}

public typealias WasiOutputHandler = @Sendable (Data) -> Int

public struct WasiOptions: Sendable {
    public var arguments: [String]?
    public var inheritArguments: Bool
    public var environment: [String: String]?
    public var inheritEnvironment: Bool
    public var standardInputBytes: [UInt8]?
    public var standardInputFile: String?
    public var inheritStandardInput: Bool
    public var standardOutputHandler: WasiOutputHandler?
    public var standardOutputFile: String?
    public var inheritStandardOutput: Bool
    public var standardErrorHandler: WasiOutputHandler?
    public var standardErrorFile: String?
    public var inheritStandardError: Bool
    public var preopenedDirectories: [WasiPreopenedDirectory]

    public init(
        arguments: [String]? = nil,
        inheritArguments: Bool = false,
        environment: [String: String]? = nil,
        inheritEnvironment: Bool = false,
        standardInputBytes: [UInt8]? = nil,
        standardInputFile: String? = nil,
        inheritStandardInput: Bool = false,
        standardOutputHandler: WasiOutputHandler? = nil,
        standardOutputFile: String? = nil,
        inheritStandardOutput: Bool = false,
        standardErrorHandler: WasiOutputHandler? = nil,
        standardErrorFile: String? = nil,
        inheritStandardError: Bool = false,
        preopenedDirectories: [WasiPreopenedDirectory] = []
    ) {
        self.arguments = arguments
        self.inheritArguments = inheritArguments
        self.environment = environment
        self.inheritEnvironment = inheritEnvironment
        self.standardInputBytes = standardInputBytes
        self.standardInputFile = standardInputFile
        self.inheritStandardInput = inheritStandardInput
        self.standardOutputHandler = standardOutputHandler
        self.standardOutputFile = standardOutputFile
        self.inheritStandardOutput = inheritStandardOutput
        self.standardErrorHandler = standardErrorHandler
        self.standardErrorFile = standardErrorFile
        self.inheritStandardError = inheritStandardError
        self.preopenedDirectories = preopenedDirectories
    }

    func makeConfig() throws -> WasiConfig {
        let config = try WasiConfig()
        if let arguments {
            try config.setArguments(arguments)
        }
        if inheritArguments {
            config.inheritArguments()
        }
        if let environment {
            try config.setEnvironment(environment)
        }
        if inheritEnvironment {
            config.inheritEnvironment()
        }
        if let standardInputBytes {
            config.setStandardInputBytes(standardInputBytes)
        }
        if let standardInputFile {
            try config.setStandardInputFile(standardInputFile)
        }
        if inheritStandardInput {
            config.inheritStandardInput()
        }
        if let standardOutputHandler {
            config.setStandardOutputHandler(standardOutputHandler)
        }
        if let standardOutputFile {
            try config.setStandardOutputFile(standardOutputFile)
        }
        if inheritStandardOutput {
            config.inheritStandardOutput()
        }
        if let standardErrorHandler {
            config.setStandardErrorHandler(standardErrorHandler)
        }
        if let standardErrorFile {
            try config.setStandardErrorFile(standardErrorFile)
        }
        if inheritStandardError {
            config.inheritStandardError()
        }
        for directory in preopenedDirectories {
            try config.preopenDirectory(
                hostPath: directory.hostPath,
                guestPath: directory.guestPath,
                directoryPermissions: directory.directoryPermissions,
                filePermissions: directory.filePermissions
            )
        }
        return config
    }
}

public struct WasiPreopenedDirectory: Sendable, Equatable {
    public var hostPath: String
    public var guestPath: String
    public var directoryPermissions: WasiDirectoryPermissions
    public var filePermissions: WasiFilePermissions

    public init(
        hostPath: String,
        guestPath: String,
        directoryPermissions: WasiDirectoryPermissions = [.read],
        filePermissions: WasiFilePermissions = [.read]
    ) {
        self.hostPath = hostPath
        self.guestPath = guestPath
        self.directoryPermissions = directoryPermissions
        self.filePermissions = filePermissions
    }
}

public struct WasiDirectoryPermissions: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let read = Self(rawValue: Int(WASMTIME_WASI_DIR_PERMS_READ.rawValue))
    public static let write = Self(rawValue: Int(WASMTIME_WASI_DIR_PERMS_WRITE.rawValue))
}

public struct WasiFilePermissions: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let read = Self(rawValue: Int(WASMTIME_WASI_FILE_PERMS_READ.rawValue))
    public static let write = Self(rawValue: Int(WASMTIME_WASI_FILE_PERMS_WRITE.rawValue))
}

public enum ValueKind: Sendable, Equatable, CustomStringConvertible {
    case i32
    case i64
    case f32
    case f64

    var wasmRawValue: wasm_valkind_t {
        switch self {
        case .i32: wasm_valkind_t(WASM_I32.rawValue)
        case .i64: wasm_valkind_t(WASM_I64.rawValue)
        case .f32: wasm_valkind_t(WASM_F32.rawValue)
        case .f64: wasm_valkind_t(WASM_F64.rawValue)
        }
    }

    public var description: String {
        switch self {
        case .i32: "i32"
        case .i64: "i64"
        case .f32: "f32"
        case .f64: "f64"
        }
    }
}

public struct FunctionType: Sendable, Equatable {
    public var parameters: [ValueKind]
    public var results: [ValueKind]

    public init(parameters: [ValueKind] = [], results: [ValueKind] = []) {
        self.parameters = parameters
        self.results = results
    }

    func makeRaw() throws -> OpaquePointer {
        var params = try Self.makeValueTypeVector(parameters)
        var results = try Self.makeValueTypeVector(results)
        guard let type = wasm_functype_new(&params, &results) else { // coverage:ignore defensive C allocation failure
            wasm_valtype_vec_delete(&params) // coverage:ignore defensive C allocation failure
            wasm_valtype_vec_delete(&results) // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasm_functype_new returned nil") // coverage:ignore defensive C allocation failure
        }
        return type
    }

    private static func makeValueTypeVector(_ kinds: [ValueKind]) throws -> wasm_valtype_vec_t {
        var vector = wasm_valtype_vec_t()
        guard !kinds.isEmpty else {
            wasm_valtype_vec_new_empty(&vector)
            return vector
        }

        let types = try kinds.map { kind -> OpaquePointer? in
            guard let raw = wasm_valtype_new(kind.wasmRawValue) else { // coverage:ignore defensive C allocation failure
                throw WasmtimeError.allocationFailed("wasm_valtype_new returned nil") // coverage:ignore defensive C allocation failure
            }
            return raw
        }
        types.withUnsafeBufferPointer { buffer in
            wasm_valtype_vec_new(&vector, buffer.count, buffer.baseAddress)
        }
        return vector
    }
}

public enum Value: Sendable, Equatable, CustomStringConvertible {
    case i32(Int32)
    case i64(Int64)
    case f32(Float)
    case f64(Double)

    var rawValue: wasmtime_val_t {
        var raw = wasmtime_val_t()
        switch self {
        case .i32(let value):
            raw.kind = wasmtime_valkind_t(WASMTIME_I32)
            raw.of.i32 = value
        case .i64(let value):
            raw.kind = wasmtime_valkind_t(WASMTIME_I64)
            raw.of.i64 = value
        case .f32(let value):
            raw.kind = wasmtime_valkind_t(WASMTIME_F32)
            raw.of.f32 = value
        case .f64(let value):
            raw.kind = wasmtime_valkind_t(WASMTIME_F64)
            raw.of.f64 = value
        }
        return raw
    }

    public var kind: ValueKind {
        switch self {
        case .i32: .i32
        case .i64: .i64
        case .f32: .f32
        case .f64: .f64
        }
    }

    init(rawValue: wasmtime_val_t) throws {
        switch rawValue.kind {
        case wasmtime_valkind_t(WASMTIME_I32):
            self = .i32(rawValue.of.i32)
        case wasmtime_valkind_t(WASMTIME_I64):
            self = .i64(rawValue.of.i64)
        case wasmtime_valkind_t(WASMTIME_F32):
            self = .f32(rawValue.of.f32)
        case wasmtime_valkind_t(WASMTIME_F64):
            self = .f64(rawValue.of.f64)
        default:
            throw WasmtimeError.unsupportedValueKind(Int(rawValue.kind))
        }
    }

    public var description: String {
        switch self {
        case .i32(let value): "i32(\(value))"
        case .i64(let value): "i64(\(value))"
        case .f32(let value): "f32(\(value))"
        case .f64(let value): "f64(\(value))"
        }
    }
}

public typealias HostFunction = @Sendable (_ caller: Caller, _ arguments: [Value]) throws -> [Value]
public typealias SendableHostFunction = @Sendable (_ arguments: [Value]) throws -> [Value]

public struct RuntimeHostFunction: Sendable {
    public var module: String
    public var name: String
    public var type: FunctionType
    public var body: SendableHostFunction

    public init(
        module: String,
        name: String,
        type: FunctionType,
        body: @escaping SendableHostFunction
    ) {
        self.module = module
        self.name = name
        self.type = type
        self.body = body
    }

    public init(
        module: String,
        name: String,
        parameters: [ValueKind] = [],
        results: [ValueKind] = [],
        body: @escaping SendableHostFunction
    ) {
        self.init(module: module, name: name, type: FunctionType(parameters: parameters, results: results), body: body)
    }
}

public struct Trap: Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public let code: UInt8?

    public var description: String {
        if let code {
            return "\(message) (trap code \(code))"
        }
        return message
    }

    static func fromOwned(_ raw: OpaquePointer) -> Trap {
        defer { wasm_trap_delete(raw) }
        var message = wasm_message_t()
        wasm_trap_message(raw, &message)
        defer { wasm_byte_vec_delete(&message) }

        var code: wasmtime_trap_code_t = 0
        let hasCode = wasmtime_trap_code(raw, &code)
        return Trap(message: String(wasmByteVec: message), code: hasCode ? code : nil)
    }
}

public enum WasmtimeError: Error, Sendable, Equatable, CustomStringConvertible {
    case api(message: String, exitStatus: Int32?)
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
        return .api(message: String(wasmByteVec: message), exitStatus: hasExitStatus ? exitStatus : nil)
    }
}

public enum WasmText {
    public static func compile(_ wat: String) throws -> [UInt8] {
        var output = wasm_byte_vec_t()
        let error = wat.withCString { cWat in
            wasmtime_wat2wasm(cWat, strlen(cWat), &output)
        }
        try WasmtimeError.throwIfNeeded(error)
        defer { wasm_byte_vec_delete(&output) }
        return output.withUnsafeBytes { Array($0) }
    }
}

public enum ExternKind: Sendable, Equatable, CustomStringConvertible {
    case function
    case global
    case table
    case memory
    case sharedMemory
    case tag
    case unknown(UInt8)

    init(rawValue: wasmtime_extern_kind_t) {
        switch rawValue {
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_FUNC): self = .function
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_GLOBAL): self = .global
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_TABLE): self = .table
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_MEMORY): self = .memory
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_SHAREDMEMORY): self = .sharedMemory
        case wasmtime_extern_kind_t(WASMTIME_EXTERN_TAG): self = .tag
        default: self = .unknown(UInt8(rawValue))
        }
    }

    public var description: String {
        switch self {
        case .function: "func"
        case .global: "global"
        case .table: "table"
        case .memory: "memory"
        case .sharedMemory: "sharedMemory"
        case .tag: "tag"
        case .unknown(let value): "unknown(\(value))"
        }
    }
}

private final class HostFunctionBox {
    let type: FunctionType
    let body: HostFunction

    init(type: FunctionType, body: @escaping HostFunction) {
        self.type = type
        self.body = body
    }
}

private final class CallerState {
    private let lock = NSLock()
    private var raw: OpaquePointer?
    private var isExpired = false

    init(raw: OpaquePointer?) {
        self.raw = raw
    }

    func currentRaw() throws -> OpaquePointer? {
        try lock.withLock {
            guard !isExpired else {
                throw WasmtimeError.callerExpired
            }
            return raw
        }
    }

    func invalidate() {
        lock.withLock {
            isExpired = true
            raw = nil
        }
    }
}

private let hostFunctionCallback: wasmtime_func_callback_t = { data, caller, args, nargs, results, nresults in
    guard let data else {
        return makeHostTrap("missing host function data") // coverage:ignore defensive C callback invariant
    }

    let box = Unmanaged<HostFunctionBox>.fromOpaque(data).takeUnretainedValue()
    do {
        let arguments = try convertHostArguments(args, count: nargs)
        let caller = Caller(raw: caller)
        defer { caller.invalidate() }
        let values = try box.body(caller, arguments)
        guard values.count == nresults else {
            return makeHostTrap("host function returned \(values.count) results, expected \(nresults)")
        }
        for (index, value) in values.enumerated() {
            let expectedKind = box.type.results[index]
            guard value.kind == expectedKind else {
                return makeHostTrap("host function returned \(value.kind) at result \(index), expected \(expectedKind)")
            }
            results![index] = value.rawValue
        }
        return nil
    } catch {
        return makeHostTrap(String(describing: error))
    }
}

private let hostFunctionFinalizer: (@convention(c) (UnsafeMutableRawPointer?) -> Void) = { data in
    if let data {
        Unmanaged<HostFunctionBox>.fromOpaque(data).release()
    }
}

private func convertHostArguments(_ args: UnsafePointer<wasmtime_val_t>?, count: Int) throws -> [Value] {
    guard count > 0 else {
        return []
    }
    guard let args else { // coverage:ignore defensive C invariant
        return []
    }
    return try (0..<count).map { index in
        try Value(rawValue: args[index])
    }
}

private func makeHostTrap(_ message: String) -> OpaquePointer? {
    message.withCString { cMessage in
        wasmtime_trap_new(cMessage, strlen(cMessage))
    }
}

private func withCStringArray<T>(_ strings: [String], _ body: (UnsafeMutableBufferPointer<UnsafePointer<CChar>?>) throws -> T) rethrows -> T {
    let cStrings = strings.map { strdup($0) }
    defer {
        for pointer in cStrings {
            free(pointer)
        }
    }
    var pointers = cStrings.map { pointer -> UnsafePointer<CChar>? in
        guard let pointer else { return nil } // coverage:ignore defensive libc allocation failure
        return UnsafePointer(pointer)
    }
    return try pointers.withUnsafeMutableBufferPointer { buffer in
        try body(buffer)
    }
}

private final class WasiOutputHandlerBox {
    let handler: WasiOutputHandler

    init(_ handler: @escaping WasiOutputHandler) {
        self.handler = handler
    }
}

private func wasiOutputHandlerCallback(
    data: UnsafeMutableRawPointer?,
    buffer: UnsafePointer<CUnsignedChar>?,
    size: Int
) -> Int {
    guard let data, let buffer else { // coverage:ignore defensive C callback invariant
        return -1
    }
    let box = Unmanaged<WasiOutputHandlerBox>.fromOpaque(data).takeUnretainedValue()
    let output = Data(bytes: buffer, count: size)
    return box.handler(output)
}

private func wasiOutputHandlerFinalizer(data: UnsafeMutableRawPointer?) {
    guard let data else { // coverage:ignore defensive C callback invariant
        return
    }
    Unmanaged<WasiOutputHandlerBox>.fromOpaque(data).release()
}

private extension wasm_byte_vec_t {
    func withUnsafeBytes<T>(_ body: (UnsafeBufferPointer<UInt8>) throws -> T) rethrows -> T {
        let start = data.map { UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self) }
        return try body(UnsafeBufferPointer(start: start, count: size))
    }
}

private extension String {
    init(wasmByteVec bytes: wasm_byte_vec_t) {
        guard bytes.size > 0, let bytesPointer = bytes.data else {
            self = ""
            return
        }
        let data = Data(bytes: UnsafeRawPointer(bytesPointer), count: bytes.size)
        self = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self) // coverage:ignore defensive invalid UTF-8 fallback
    }
}
