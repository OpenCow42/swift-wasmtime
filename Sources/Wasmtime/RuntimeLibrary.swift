#if os(Windows)
import Foundation
import WinSDK

private let wasmtimeRuntimeLibraryConfigured: Void = {
    let directory = vendoredWasmtimeLibraryDirectory()
    let dll = directory + "\\wasmtime.dll"

    guard FileManager.default.fileExists(atPath: dll) else {
        return
    }

    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    let entries = path.split(separator: ";", omittingEmptySubsequences: false)
    let isAlreadyPresent = entries.contains { entry in
        entry.compare(directory, options: [.caseInsensitive]) == .orderedSame
    }

    guard !isAlreadyPresent else {
        return
    }

    setWindowsEnvironmentVariable("PATH", directory + ";" + path)
}()

@inline(__always)
func ensureWasmtimeRuntimeLibraryIsDiscoverable() {
    _ = wasmtimeRuntimeLibraryConfigured
}

private func vendoredWasmtimeLibraryDirectory() -> String {
    let sourcePath = String(#filePath).replacingOccurrences(of: "/", with: "\\")
    let marker = "\\Sources\\Wasmtime\\RuntimeLibrary.swift"
    let packageRoot: String

    if let markerRange = sourcePath.range(of: marker, options: [.caseInsensitive, .backwards]) {
        packageRoot = String(sourcePath[..<markerRange.lowerBound])
    } else {
        packageRoot = FileManager.default.currentDirectoryPath
    }

    return packageRoot + "\\Vendor\\Wasmtime\\v45.0.2\\" + wasmtimeVendorPlatform + "\\lib"
}

private var wasmtimeVendorPlatform: String {
#if arch(x86_64)
    "x86_64-windows"
#elseif arch(arm64)
    "aarch64-windows"
#else
#error("Wasmtime currently supports x86_64 and arm64 on Windows")
#endif
}

private func setWindowsEnvironmentVariable(_ name: String, _ value: String) {
    _ = name.withCString(encodedAs: UTF16.self) { wideName in
        value.withCString(encodedAs: UTF16.self) { wideValue in
            SetEnvironmentVariableW(wideName, wideValue)
        }
    }
}
#endif
