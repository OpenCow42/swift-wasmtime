import Foundation
@preconcurrency import CWasmtime

#if os(Linux)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Action to take after an epoch deadline callback fires.
public enum EpochDeadlineAction: Sendable, Equatable {
    /// Continue execution and set the next relative deadline.
    case `continue`(ticksBeyondCurrent: UInt64)
}

/// Handler used when a store reaches its configured epoch deadline.
///
/// Return `.continue(ticksBeyondCurrent:)` to continue execution. Throw to
/// terminate execution with a Wasmtime error. Async yielding is intentionally
/// not exposed until Wasmtime async support has a Swift API.
public typealias EpochDeadlineHandler = @Sendable (_ currentDeadlineDelta: UInt64) throws -> EpochDeadlineAction

/// Low-level Wasmtime store wrapper.
///
/// `Store` owns store-bound Wasmtime objects such as instances and functions.
/// It is not `Sendable`; serialize access yourself or use `WasmtimeRuntime`.
/// Store-bound handles should only be used with the store that owns them.
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

    /// Applies resource limits to future resource creation and growth.
    public func setResourceLimits(_ limits: ResourceLimits) {
        wasmtime_store_limiter(
            raw,
            limits.memorySizeBytes ?? -1,
            limits.tableElements ?? -1,
            limits.instances ?? -1,
            limits.tables ?? -1,
            limits.memories ?? -1
        )
    }

    /// Runs a garbage collection pass for GC-managed values in this store.
    public func collectGarbage() throws {
        try WasmtimeError.throwIfNeeded(wasmtime_context_gc(context))
    }

    /// Sets the fuel available to guest code in this store.
    ///
    /// Fuel consumption must be enabled on the engine configuration.
    public func setFuel(_ fuel: UInt64) throws {
        try WasmtimeError.throwIfNeeded(wasmtime_context_set_fuel(context, fuel))
    }

    /// Returns the fuel remaining for guest code in this store.
    ///
    /// Fuel consumption must be enabled on the engine configuration.
    public func fuel() throws -> UInt64 {
        var fuel: UInt64 = 0
        try WasmtimeError.throwIfNeeded(wasmtime_context_get_fuel(context, &fuel))
        return fuel
    }

    /// Sets the store-local epoch deadline relative to the engine's current epoch.
    public func setEpochDeadline(ticksBeyondCurrent: UInt64) {
        wasmtime_context_set_epoch_deadline(context, ticksBeyondCurrent)
    }

    /// Installs a callback invoked when guest code reaches this store's epoch deadline.
    public func setEpochDeadlineCallback(_ callback: @escaping EpochDeadlineHandler) {
        let box = Unmanaged.passRetained(EpochDeadlineCallbackBox(callback))
        wasmtime_store_epoch_deadline_callback(
            raw,
            epochDeadlineCallback,
            box.toOpaque(),
            epochDeadlineCallbackFinalizer
        )
    }

    /// Installs WASI configuration into this store.
    ///
    /// This consumes `config`. Do not use the same `WasiConfig` again after
    /// calling this method. Prefer `WasiOptions` when possible.
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

private final class EpochDeadlineCallbackBox {
    let body: EpochDeadlineHandler

    init(_ body: @escaping EpochDeadlineHandler) {
        self.body = body
    }
}

private let epochDeadlineCallback:
    (@convention(c) (
        OpaquePointer?,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<UInt64>?,
        UnsafeMutablePointer<wasmtime_update_deadline_kind_t>?
    ) -> OpaquePointer?) = { _, data, epochDeadlineDelta, updateKind in
        guard let data else {
            return makeHostError("missing epoch deadline callback data") // coverage:ignore defensive C callback invariant
        }
        guard let epochDeadlineDelta, let updateKind else {
            return makeHostError("missing epoch deadline callback output") // coverage:ignore defensive C callback invariant
        }

        let box = Unmanaged<EpochDeadlineCallbackBox>.fromOpaque(data).takeUnretainedValue()
        do {
            switch try box.body(epochDeadlineDelta.pointee) {
            case .continue(let ticksBeyondCurrent):
                epochDeadlineDelta.pointee = ticksBeyondCurrent
                updateKind.pointee = wasmtime_update_deadline_kind_t(WASMTIME_UPDATE_DEADLINE_CONTINUE)
            }
            return nil
        } catch {
            return makeHostError(String(describing: error))
        }
    }

private let epochDeadlineCallbackFinalizer: (@convention(c) (UnsafeMutableRawPointer?) -> Void) = { data in
    if let data {
        Unmanaged<EpochDeadlineCallbackBox>.fromOpaque(data).release()
    }
}

private func makeHostError(_ message: String) -> OpaquePointer? {
    message.withCString { cMessage in
        wasmtime_error_new(cMessage)
    }
}
