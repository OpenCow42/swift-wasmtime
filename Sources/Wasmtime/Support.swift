import Foundation
@preconcurrency import CWasmtime

#if os(Linux)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

extension wasm_byte_vec_t {
    func withUnsafeBytes<T>(_ body: (UnsafeBufferPointer<UInt8>) throws -> T) rethrows -> T {
        let start = data.map { UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self) }
        return try body(UnsafeBufferPointer(start: start, count: size))
    }
}

extension String {
    init(wasmByteVec bytes: wasm_byte_vec_t) {
        guard bytes.size > 0, let bytesPointer = bytes.data else {
            self = ""
            return
        }
        let data = Data(bytes: UnsafeRawPointer(bytesPointer), count: bytes.size)
        self = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self) // coverage:ignore defensive invalid UTF-8 fallback
    }
}
