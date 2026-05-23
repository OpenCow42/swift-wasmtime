import Foundation
import Testing
@preconcurrency import CWasmtime
@testable import Wasmtime

func acceptsSendable<T: Sendable>(_ value: T) {
    _ = value
}

func testTemporaryDirectory() -> URL {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build", isDirectory: true)
        .appendingPathComponent("test-tmp", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

final class LockedOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [UInt8] = []

    func append(_ data: Data) {
        lock.withLock {
            bytes.append(contentsOf: data)
        }
    }

    func string() -> String {
        lock.withLock {
            String(decoding: bytes, as: UTF8.self)
        }
    }
}

final class LockedCallerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var caller: Caller?

    func set(_ caller: Caller) {
        lock.withLock {
            self.caller = caller
        }
    }

    func get() -> Caller? {
        lock.withLock {
            caller
        }
    }
}

final class LockedInt: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.withLock {
            storage += 1
        }
    }

    func value() -> Int {
        lock.withLock {
            storage
        }
    }
}

let nativeSIMDFlag = {
    #if arch(x86_64)
    "has_sse2"
    #elseif arch(arm64)
    "has_neon"
    #else
    "is_pic"
    #endif
}()

let nativeTargetTriple = {
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

let componentRunWat = """
(component
  (core module $m
    (func (export "run")))
  (core instance $i (instantiate $m))
  (func (export "run") (canon lift (core func $i "run"))))
"""

let simdWat = """
(module
  (func (export "simd") (result v128)
    v128.const i32x4 1 2 3 4))
"""

let countedLoopWat = """
(module
  (func (export "count") (param $n i32) (result i32)
    (local $acc i32)
    block $exit
      loop $loop
        local.get $n
        i32.eqz
        br_if $exit
        local.get $n
        i32.const 1
        i32.sub
        local.set $n
        local.get $acc
        i32.const 1
        i32.add
        local.set $acc
        br $loop
      end
    end
    local.get $acc))
"""

let wasiStdioWat = """
(module
  (import "wasi_snapshot_preview1" "fd_read" (func $fd_read (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory 1)
  (export "memory" (memory 0))
  (data (i32.const 160) "callback-stderr\\n")
  (func $write (param $fd i32) (param $ptr i32) (param $len i32)
    i32.const 24
    local.get $ptr
    i32.store
    i32.const 28
    local.get $len
    i32.store
    local.get $fd
    i32.const 24
    i32.const 1
    i32.const 32
    call $fd_write
    drop)
  (func (export "_start")
    i32.const 0
    i32.const 64
    i32.store
    i32.const 4
    i32.const 32
    i32.store
    i32.const 0
    i32.const 0
    i32.const 1
    i32.const 16
    call $fd_read
    drop
    i32.const 1
    i32.const 64
    i32.const 16
    i32.load
    call $write
    i32.const 2
    i32.const 160
    i32.const 16
    call $write))
"""

func expectWasmtimeError(_ body: () throws -> Void) throws {
    do {
        try body()
        Issue.record("expected WasmtimeError")
    } catch let error as WasmtimeError {
        #expect(!error.description.isEmpty)
    }
}

func expectSpecificError(_ expected: WasmtimeError, _ body: () throws -> Void) throws {
    do {
        try body()
        Issue.record("expected \(expected)")
    } catch let error as WasmtimeError {
        #expect(error == expected)
    }
}
