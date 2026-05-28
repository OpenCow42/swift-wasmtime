import Foundation
@preconcurrency import CWasmtime

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

/// Low-level mutable engine configuration.
///
/// `Config` mirrors Wasmtime's C API builder object and is consumed by
/// `Engine.init(config:)`. Do not use a `Config` again after passing it to an
/// `Engine`; prefer `EngineOptions` for reusable, sendable configuration.
public final class Config {
    private var raw: OpaquePointer?

    public init() throws {
        ensureWasmtimeRuntimeLibraryIsDiscoverable()

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

    public var isSharedMemoryEnabled: Bool = false {
        didSet {
            wasmtime_config_shared_memory_set(requiredRaw, isSharedMemoryEnabled)
        }
    }

    public var isTailCallEnabled: Bool = false {
        didSet {
            wasmtime_config_wasm_tail_call_set(requiredRaw, isTailCallEnabled)
        }
    }

    public var isReferenceTypesEnabled: Bool = true {
        didSet {
            wasmtime_config_wasm_reference_types_set(requiredRaw, isReferenceTypesEnabled)
        }
    }

    public var isFunctionReferencesEnabled: Bool = false {
        didSet {
            wasmtime_config_wasm_function_references_set(requiredRaw, isFunctionReferencesEnabled)
        }
    }

    public var isWasmGCEnabled: Bool = false {
        didSet {
            wasmtime_config_wasm_gc_set(requiredRaw, isWasmGCEnabled)
        }
    }

    public var isGCSupportEnabled: Bool = true {
        didSet {
            wasmtime_config_gc_support_set(requiredRaw, isGCSupportEnabled)
        }
    }

    public var isBulkMemoryEnabled: Bool = true {
        didSet {
            wasmtime_config_wasm_bulk_memory_set(requiredRaw, isBulkMemoryEnabled)
        }
    }

    public var isMultiValueEnabled: Bool = true {
        didSet {
            wasmtime_config_wasm_multi_value_set(requiredRaw, isMultiValueEnabled)
        }
    }

    public var isMultiMemoryEnabled: Bool = true {
        didSet {
            wasmtime_config_wasm_multi_memory_set(requiredRaw, isMultiMemoryEnabled)
        }
    }

    public var isMemory64Enabled: Bool = false {
        didSet {
            wasmtime_config_wasm_memory64_set(requiredRaw, isMemory64Enabled)
        }
    }

    public var isWideArithmeticEnabled: Bool = false {
        didSet {
            wasmtime_config_wasm_wide_arithmetic_set(requiredRaw, isWideArithmeticEnabled)
        }
    }

    public var areExceptionsEnabled: Bool = false {
        didSet {
            wasmtime_config_wasm_exceptions_set(requiredRaw, areExceptionsEnabled)
        }
    }

    public var areCustomPageSizesEnabled: Bool = false {
        didSet {
            wasmtime_config_wasm_custom_page_sizes_set(requiredRaw, areCustomPageSizesEnabled)
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

    public var craneliftRegallocAlgorithm: CraneliftRegallocAlgorithm = .backtracking {
        didSet {
            wasmtime_config_cranelift_regalloc_algorithm_set(requiredRaw, craneliftRegallocAlgorithm.rawValue)
        }
    }

    public var isCraneliftDebugVerifierEnabled: Bool = false {
        didSet {
            wasmtime_config_cranelift_debug_verifier_set(requiredRaw, isCraneliftDebugVerifierEnabled)
        }
    }

    public var isCraneliftNaNCanonicalizationEnabled: Bool = false {
        didSet {
            wasmtime_config_cranelift_nan_canonicalization_set(requiredRaw, isCraneliftNaNCanonicalizationEnabled)
        }
    }

    public var profiler: ProfilingStrategy = .none {
        didSet {
            wasmtime_config_profiler_set(requiredRaw, profiler.rawValue)
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

    public var nativeUnwindInfo: Bool = true {
        didSet {
            wasmtime_config_native_unwind_info_set(requiredRaw, nativeUnwindInfo)
        }
    }

    public var usesMachPortsOnMacOS: Bool = true {
        didSet {
            wasmtime_config_macos_use_mach_ports_set(requiredRaw, usesMachPortsOnMacOS)
        }
    }

    public var usesMemoryInitCopyOnWrite: Bool = true {
        didSet {
            wasmtime_config_memory_init_cow_set(requiredRaw, usesMemoryInitCopyOnWrite)
        }
    }

    public var consumesFuel: Bool = false {
        didSet {
            wasmtime_config_consume_fuel_set(requiredRaw, consumesFuel)
        }
    }

    public var usesEpochInterruption: Bool = false {
        didSet {
            wasmtime_config_epoch_interruption_set(requiredRaw, usesEpochInterruption)
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

    public func setMaxWasmStack(_ bytes: Int) {
        wasmtime_config_max_wasm_stack_set(requiredRaw, bytes)
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
        isSharedMemoryEnabled = options.isSharedMemoryEnabled
        isTailCallEnabled = options.isTailCallEnabled
        isReferenceTypesEnabled = options.isReferenceTypesEnabled
        isFunctionReferencesEnabled = options.isFunctionReferencesEnabled
        isWasmGCEnabled = options.isWasmGCEnabled
        isGCSupportEnabled = options.isGCSupportEnabled
        isBulkMemoryEnabled = options.isBulkMemoryEnabled
        isMultiValueEnabled = options.isMultiValueEnabled
        isMultiMemoryEnabled = options.isMultiMemoryEnabled
        isMemory64Enabled = options.isMemory64Enabled
        isWideArithmeticEnabled = options.isWideArithmeticEnabled
        areExceptionsEnabled = options.areExceptionsEnabled
        areCustomPageSizesEnabled = options.areCustomPageSizesEnabled
        strategy = options.strategy
        craneliftOptimizationLevel = options.craneliftOptimizationLevel
        craneliftRegallocAlgorithm = options.craneliftRegallocAlgorithm
        isCraneliftDebugVerifierEnabled = options.isCraneliftDebugVerifierEnabled
        isCraneliftNaNCanonicalizationEnabled = options.isCraneliftNaNCanonicalizationEnabled
        profiler = options.profiler
        memoryMayMove = options.memoryMayMove
        signalsBasedTraps = options.signalsBasedTraps
        debugInfo = options.debugInfo
        parallelCompilation = options.parallelCompilation
        nativeUnwindInfo = options.nativeUnwindInfo
        usesMachPortsOnMacOS = options.usesMachPortsOnMacOS
        usesMemoryInitCopyOnWrite = options.usesMemoryInitCopyOnWrite
        consumesFuel = options.interruption.consumesFuel
        usesEpochInterruption = options.interruption.usesEpochInterruption

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
        if let maxWasmStack = options.interruption.maxWasmStack {
            setMaxWasmStack(maxWasmStack)
        }
    }
}

/// Sendable engine-level interruption configuration.
///
/// Fuel and epoch interruption must be enabled before the corresponding
/// `Store` methods can control execution.
public struct InterruptionOptions: Sendable, Equatable {
    public var consumesFuel: Bool
    public var usesEpochInterruption: Bool
    public var maxWasmStack: Int?

    public init(
        consumesFuel: Bool = false,
        usesEpochInterruption: Bool = false,
        maxWasmStack: Int? = nil
    ) {
        self.consumesFuel = consumesFuel
        self.usesEpochInterruption = usesEpochInterruption
        self.maxWasmStack = maxWasmStack
    }
}

/// Sendable engine configuration used by the actor-oriented API.
///
/// Use this value type when configuration must cross Swift concurrency domains.
/// It is applied to an internal `Config` when constructing an `Engine`.
public struct EngineOptions: Sendable, Equatable {
    public var isComponentModelEnabled: Bool
    public var isSIMDEnabled: Bool
    public var isRelaxedSIMDEnabled: Bool
    public var isRelaxedSIMDDeterministic: Bool
    public var isSharedMemoryEnabled: Bool
    public var isTailCallEnabled: Bool
    public var isReferenceTypesEnabled: Bool
    public var isFunctionReferencesEnabled: Bool
    public var isWasmGCEnabled: Bool
    public var isGCSupportEnabled: Bool
    public var isBulkMemoryEnabled: Bool
    public var isMultiValueEnabled: Bool
    public var isMultiMemoryEnabled: Bool
    public var isMemory64Enabled: Bool
    public var isWideArithmeticEnabled: Bool
    public var areExceptionsEnabled: Bool
    public var areCustomPageSizesEnabled: Bool
    public var strategy: CompilationStrategy
    public var craneliftOptimizationLevel: CraneliftOptimizationLevel
    public var craneliftRegallocAlgorithm: CraneliftRegallocAlgorithm
    public var isCraneliftDebugVerifierEnabled: Bool
    public var isCraneliftNaNCanonicalizationEnabled: Bool
    public var profiler: ProfilingStrategy
    public var memoryMayMove: Bool
    public var signalsBasedTraps: Bool
    public var debugInfo: Bool
    public var parallelCompilation: Bool
    public var nativeUnwindInfo: Bool
    public var usesMachPortsOnMacOS: Bool
    public var usesMemoryInitCopyOnWrite: Bool
    public var target: String?
    public var enabledCraneliftFlags: [String]
    public var craneliftFlagValues: [String: String]
    public var memoryReservation: UInt64?
    public var memoryGuardSize: UInt64?
    public var memoryReservationForGrowth: UInt64?
    public var interruption: InterruptionOptions

    public init(
        isComponentModelEnabled: Bool = false,
        isSIMDEnabled: Bool = false,
        isRelaxedSIMDEnabled: Bool = false,
        isRelaxedSIMDDeterministic: Bool = false,
        isSharedMemoryEnabled: Bool = false,
        isTailCallEnabled: Bool = false,
        isReferenceTypesEnabled: Bool = true,
        isFunctionReferencesEnabled: Bool = false,
        isWasmGCEnabled: Bool = false,
        isGCSupportEnabled: Bool = true,
        isBulkMemoryEnabled: Bool = true,
        isMultiValueEnabled: Bool = true,
        isMultiMemoryEnabled: Bool = true,
        isMemory64Enabled: Bool = false,
        isWideArithmeticEnabled: Bool = false,
        areExceptionsEnabled: Bool = false,
        areCustomPageSizesEnabled: Bool = false,
        strategy: CompilationStrategy = .automatic,
        craneliftOptimizationLevel: CraneliftOptimizationLevel = .speed,
        craneliftRegallocAlgorithm: CraneliftRegallocAlgorithm = .backtracking,
        isCraneliftDebugVerifierEnabled: Bool = false,
        isCraneliftNaNCanonicalizationEnabled: Bool = false,
        profiler: ProfilingStrategy = .none,
        memoryMayMove: Bool = false,
        signalsBasedTraps: Bool = true,
        debugInfo: Bool = false,
        parallelCompilation: Bool = true,
        nativeUnwindInfo: Bool = true,
        usesMachPortsOnMacOS: Bool = true,
        usesMemoryInitCopyOnWrite: Bool = true,
        target: String? = nil,
        enabledCraneliftFlags: [String] = [],
        craneliftFlagValues: [String: String] = [:],
        memoryReservation: UInt64? = nil,
        memoryGuardSize: UInt64? = nil,
        memoryReservationForGrowth: UInt64? = nil,
        interruption: InterruptionOptions = InterruptionOptions()
    ) {
        self.isComponentModelEnabled = isComponentModelEnabled
        self.isSIMDEnabled = isSIMDEnabled
        self.isRelaxedSIMDEnabled = isRelaxedSIMDEnabled
        self.isRelaxedSIMDDeterministic = isRelaxedSIMDDeterministic
        self.isSharedMemoryEnabled = isSharedMemoryEnabled
        self.isTailCallEnabled = isTailCallEnabled
        self.isReferenceTypesEnabled = isReferenceTypesEnabled
        self.isFunctionReferencesEnabled = isFunctionReferencesEnabled
        self.isWasmGCEnabled = isWasmGCEnabled
        self.isGCSupportEnabled = isGCSupportEnabled
        self.isBulkMemoryEnabled = isBulkMemoryEnabled
        self.isMultiValueEnabled = isMultiValueEnabled
        self.isMultiMemoryEnabled = isMultiMemoryEnabled
        self.isMemory64Enabled = isMemory64Enabled
        self.isWideArithmeticEnabled = isWideArithmeticEnabled
        self.areExceptionsEnabled = areExceptionsEnabled
        self.areCustomPageSizesEnabled = areCustomPageSizesEnabled
        self.strategy = strategy
        self.craneliftOptimizationLevel = craneliftOptimizationLevel
        self.craneliftRegallocAlgorithm = craneliftRegallocAlgorithm
        self.isCraneliftDebugVerifierEnabled = isCraneliftDebugVerifierEnabled
        self.isCraneliftNaNCanonicalizationEnabled = isCraneliftNaNCanonicalizationEnabled
        self.profiler = profiler
        self.memoryMayMove = memoryMayMove
        self.signalsBasedTraps = signalsBasedTraps
        self.debugInfo = debugInfo
        self.parallelCompilation = parallelCompilation
        self.nativeUnwindInfo = nativeUnwindInfo
        self.usesMachPortsOnMacOS = usesMachPortsOnMacOS
        self.usesMemoryInitCopyOnWrite = usesMemoryInitCopyOnWrite
        self.target = target
        self.enabledCraneliftFlags = enabledCraneliftFlags
        self.craneliftFlagValues = craneliftFlagValues
        self.memoryReservation = memoryReservation
        self.memoryGuardSize = memoryGuardSize
        self.memoryReservationForGrowth = memoryReservationForGrowth
        self.interruption = interruption
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

/// Wasmtime compilation backend selection.
public enum CompilationStrategy: Sendable, Equatable {
    case automatic
    case cranelift
    case winch

    var rawValue: wasmtime_strategy_t {
        switch self {
        case .automatic: wasmtime_strategy_t(WASMTIME_STRATEGY_AUTO.rawValue)
        case .cranelift: wasmtime_strategy_t(WASMTIME_STRATEGY_CRANELIFT.rawValue)
        case .winch: wasmtime_strategy_t(WASMTIME_STRATEGY_WINCH.rawValue)
        }
    }
}

/// Optimization level used by the Cranelift compiler backend.
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

/// Register allocator used by the Cranelift compiler backend.
public enum CraneliftRegallocAlgorithm: Sendable, Equatable {
    case backtracking
    case singlePass

    var rawValue: wasmtime_regalloc_algorithm_t {
        switch self {
        case .backtracking: wasmtime_regalloc_algorithm_t(WASMTIME_REGALLOC_BACKTRACKING.rawValue)
        case .singlePass: wasmtime_regalloc_algorithm_t(WASMTIME_REGALLOC_SINGLE_PASS.rawValue)
        }
    }
}

/// Profiling integration used for generated JIT code.
public enum ProfilingStrategy: Sendable, Equatable {
    case none
    case jitdump
    case vtune
    case perfmap

    var rawValue: wasmtime_profiling_strategy_t {
        switch self {
        case .none: wasmtime_profiling_strategy_t(WASMTIME_PROFILING_STRATEGY_NONE.rawValue)
        case .jitdump: wasmtime_profiling_strategy_t(WASMTIME_PROFILING_STRATEGY_JITDUMP.rawValue)
        case .vtune: wasmtime_profiling_strategy_t(WASMTIME_PROFILING_STRATEGY_VTUNE.rawValue)
        case .perfmap: wasmtime_profiling_strategy_t(WASMTIME_PROFILING_STRATEGY_PERFMAP.rawValue)
        }
    }
}

/// Wasmtime engine used to compile modules and create stores.
///
/// `Engine` is immutable after creation and may be shared across Swift
/// concurrency domains. Use a single engine for modules and stores that need to
/// interact.
public final class Engine: @unchecked Sendable {
    let raw: OpaquePointer

    public init() throws {
        ensureWasmtimeRuntimeLibraryIsDiscoverable()

        guard let raw = wasm_engine_new() else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasm_engine_new returned nil")
        }
        self.raw = raw
    }

    public init(config: Config) throws {
        ensureWasmtimeRuntimeLibraryIsDiscoverable()

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

    /// Increments this engine's epoch counter.
    ///
    /// Stores with epoch interruption enabled can use this to interrupt guest
    /// code once their configured deadline has passed.
    public func incrementEpoch() {
        wasmtime_engine_increment_epoch(raw)
    }

    deinit {
        wasm_engine_delete(raw)
    }
}
