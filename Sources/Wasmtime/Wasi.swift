import Foundation
@preconcurrency import CWasmtime

#if os(Linux)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Low-level mutable WASI configuration.
///
/// `WasiConfig` mirrors Wasmtime's C API object and is consumed by
/// `Store.setWasi(_:)`. Do not use a `WasiConfig` again after installing it in
/// a store; prefer `WasiOptions` for reusable, sendable configuration.
public final class WasiConfig {
    private var raw: OpaquePointer?

    public init() throws {
        guard let raw = wasi_config_new() else { // coverage:ignore defensive C allocation failure
            throw WasmtimeError.allocationFailed("wasi_config_new returned nil")
        }
        self.raw = raw
    }

    public func inheritNetwork() {
        wasi_config_inherit_network(requiredRaw)
    }

    public func setIPNameLookupAllowed(_ isAllowed: Bool = true) {
        wasi_config_allow_ip_name_lookup(requiredRaw, isAllowed)
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

    /// Legacy mask adapter. Wasmtime 48 accepts only read/read or full/full.
    /// Other pairs throw before access is granted; use the explicit filesystem policy.
    public func preopenDirectory(
        hostPath: String,
        guestPath: String,
        directoryPermissions: WasiDirectoryPermissions = [.read],
        filePermissions: WasiFilePermissions = [.read]
    ) throws {
        let permissions: WasiFilesystemPermissions
        switch (directoryPermissions.rawValue, filePermissions.rawValue) {
        case (1, 1):
            permissions = .readOnly
        case (3, 3):
            permissions = .readWrite
        default:
            throw WasmtimeError.wasiConfigurationFailed(
                "Wasmtime 48 supports whole-filesystem read-only or read-write preopens, " +
                "not independent directory/file permissions. Use filesystemPermissions; " +
                "the requested legacy permissions were not granted."
            )
        }
        try preopenDirectory(hostPath: hostPath, guestPath: guestPath, filesystemPermissions: permissions)
    }

    /// Grants explicitly scoped access to a directory and its descendants.
    ///
    /// Wasmtime 48 applies one filesystem permission policy to both directories
    /// and files. Read-only is the safe equivalent of the legacy read/read policy.
    public func preopenDirectory(
        hostPath: String,
        guestPath: String,
        filesystemPermissions: WasiFilesystemPermissions
    ) throws {
        try hostPath.withCString { cHostPath in
            try guestPath.withCString { cGuestPath in
                guard wasi_config_preopen_dir(
                    requiredRaw,
                    cHostPath,
                    cGuestPath,
                    filesystemPermissions == .readWrite
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

/// Handler used by custom WASI stdout and stderr streams.
///
/// Return the number of bytes accepted. The closure is `@Sendable`; capture only
/// thread-safe state or serialize access yourself.
public typealias WasiOutputHandler = @Sendable (Data) -> Int

/// Sendable WASI configuration used by `WasmtimeRuntime`.
///
/// Use this reusable value type instead of `WasiConfig` when configuration
/// needs to cross Swift concurrency domains.
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
    public var inheritNetwork: Bool
    public var allowsIPNameLookup: Bool

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
        preopenedDirectories: [WasiPreopenedDirectory] = [],
        inheritNetwork: Bool = false,
        allowsIPNameLookup: Bool = false
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
        self.inheritNetwork = inheritNetwork
        self.allowsIPNameLookup = allowsIPNameLookup
    }

    func makeConfig() throws -> WasiConfig {
        let config = try WasiConfig()
        if inheritNetwork {
            config.inheritNetwork()
        }
        if allowsIPNameLookup {
            config.setIPNameLookupAllowed()
        }
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

/// Directory mapping exposed to WASI guests.
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

    /// Creates a preopen using Wasmtime 48's native filesystem policy.
    public init(
        hostPath: String,
        guestPath: String,
        filesystemPermissions: WasiFilesystemPermissions
    ) {
        self.init(
            hostPath: hostPath,
            guestPath: guestPath,
            directoryPermissions: filesystemPermissions == .readWrite ? [.read, .write] : [.read],
            filePermissions: filesystemPermissions == .readWrite ? [.read, .write] : [.read]
        )
    }
}

/// Permissions applied to a preopened directory and every reachable file.
public enum WasiFilesystemPermissions: Sendable, Hashable {
    /// Allows reads and metadata queries; rejects filesystem mutations.
    case readOnly
    /// Allows reads and filesystem mutations within the preopened directory.
    case readWrite
}

/// Directory-level permissions for a WASI preopened directory.
public struct WasiDirectoryPermissions: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let read = Self(rawValue: 1)
    public static let write = Self(rawValue: 2)
}

/// File-level permissions for files inside a WASI preopened directory.
public struct WasiFilePermissions: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let read = Self(rawValue: 1)
    public static let write = Self(rawValue: 2)
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
