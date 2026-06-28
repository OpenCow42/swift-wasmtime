import Foundation
import Testing
@preconcurrency import CWasmtime
@testable import Wasmtime

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

@Test func wasiNetworkAndNameLookupConfigurationCanBeApplied() throws {
    let config = try WasiConfig()
    config.inheritNetwork()
    config.setIPNameLookupAllowed()
    config.setIPNameLookupAllowed(false)

    let options = WasiOptions(inheritNetwork: true, allowsIPNameLookup: true)
    acceptsSendable(options)

    let engine = try Engine()
    let store = try Store(engine: engine)
    try store.setWasi(try options.makeConfig())
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

@Test func wasiPathOpenTruncateRequiresWriteFilePermissions() throws {
    let readOnly = try runWasiTruncateAttempt(filePermissions: [.read])
    #expect(readOnly == "preserve")

    let writable = try runWasiTruncateAttempt(filePermissions: [.read, .write])
    #expect(writable == "")
}

@Test func wasiFdRenumberReplacesDestinationDescriptor() throws {
    let temporary = testTemporaryDirectory()
        .appendingPathComponent("swift-wasmtime-\(UUID().uuidString)", isDirectory: true)
    let sandbox = temporary.appendingPathComponent("sandbox", isDirectory: true)
    let source = sandbox.appendingPathComponent("source.txt")
    let destination = sandbox.appendingPathComponent("destination.txt")
    try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }

    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(engine: engine, wat: wasiFdRenumberWat)
    let wasi = try WasiConfig()
    try wasi.preopenDirectory(
        hostPath: sandbox.path,
        guestPath: "/sandbox",
        directoryPermissions: [.read, .write],
        filePermissions: [.read, .write]
    )
    try store.setWasi(wasi)
    let linker = try Linker(engine: engine)
    try linker.defineWasi()
    let instance = try linker.instantiate(store: store, module: module)

    #expect(try instance.exportedFunction(named: "_start").call() == [])
    #expect(try String(contentsOf: source, encoding: .utf8) == "after-renumber\n")
    #expect(try String(contentsOf: destination, encoding: .utf8) == "")
}

private func runWasiTruncateAttempt(filePermissions: WasiFilePermissions) throws -> String {
    let temporary = testTemporaryDirectory()
        .appendingPathComponent("swift-wasmtime-\(UUID().uuidString)", isDirectory: true)
    let sandbox = temporary.appendingPathComponent("sandbox", isDirectory: true)
    let target = sandbox.appendingPathComponent("target.txt")
    try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try "preserve".write(to: target, atomically: true, encoding: .utf8)

    let engine = try Engine()
    let store = try Store(engine: engine)
    let module = try Module(engine: engine, wat: wasiTruncateWat)
    let wasi = try WasiConfig()
    try wasi.preopenDirectory(
        hostPath: sandbox.path,
        guestPath: "/sandbox",
        directoryPermissions: [.read, .write],
        filePermissions: filePermissions
    )
    try store.setWasi(wasi)
    let linker = try Linker(engine: engine)
    try linker.defineWasi()
    let instance = try linker.instantiate(store: store, module: module)

    #expect(try instance.exportedFunction(named: "_start").call() == [])
    return try String(contentsOf: target, encoding: .utf8)
}

private let wasiTruncateWat = """
(module
  (import "wasi_snapshot_preview1" "path_open" (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (memory 1)
  (export "memory" (memory 0))
  (data (i32.const 64) "target.txt")
  (func (export "_start") (local $errno i32)
    i32.const 3
    i32.const 0
    i32.const 64
    i32.const 10
    i32.const 8
    i64.const 66
    i64.const 0
    i32.const 0
    i32.const 48
    call $path_open
    local.set $errno))
"""

private let wasiFdRenumberWat = """
(module
  (import "wasi_snapshot_preview1" "path_open" (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_close" (func $fd_close (param i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_renumber" (func $fd_renumber (param i32 i32) (result i32)))
  (memory 1)
  (export "memory" (memory 0))
  (data (i32.const 64) "source.txt")
  (data (i32.const 96) "destination.txt")
  (data (i32.const 160) "after-renumber\\n")
  (func $assertOk (param $errno i32)
    local.get $errno
    i32.eqz
    if
    else
      unreachable
    end)
  (func $openWritableFile (param $path i32) (param $length i32) (param $result i32)
    i32.const 3
    i32.const 0
    local.get $path
    local.get $length
    i32.const 9
    i64.const 66
    i64.const 0
    i32.const 0
    local.get $result
    call $path_open
    call $assertOk)
  (func $write (param $fd i32) (param $ptr i32) (param $len i32)
    i32.const 16
    local.get $ptr
    i32.store
    i32.const 20
    local.get $len
    i32.store
    local.get $fd
    i32.const 16
    i32.const 1
    i32.const 24
    call $fd_write
    call $assertOk)
  (func $close (param $fd i32)
    local.get $fd
    call $fd_close
    call $assertOk)
  (func (export "_start")
    i32.const 64
    i32.const 10
    i32.const 48
    call $openWritableFile
    i32.const 96
    i32.const 15
    i32.const 52
    call $openWritableFile
    i32.const 48
    i32.load
    i32.const 52
    i32.load
    call $fd_renumber
    call $assertOk
    i32.const 52
    i32.load
    i32.const 160
    i32.const 15
    call $write
    i32.const 52
    i32.load
    call $close))
"""
