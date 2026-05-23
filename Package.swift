// swift-tools-version: 6.3

import PackageDescription

#if os(macOS)
let wasmtimeOS = "macos"
#elseif os(Linux)
let wasmtimeOS = "linux"
#else
#error("Wasmtime currently supports macOS and Linux")
#endif

#if arch(arm64)
let wasmtimeArch = "aarch64"
#elseif arch(x86_64)
let wasmtimeArch = "x86_64"
#else
#error("Wasmtime currently supports arm64 and x86_64")
#endif

let wasmtimeVersion = "v44.0.1"
let wasmtimeLibraryPath = "Vendor/Wasmtime/\(wasmtimeVersion)/\(wasmtimeArch)-\(wasmtimeOS)/lib"

let package = Package(
    name: "Wasmtime",
    products: [
        .library(
            name: "Wasmtime",
            targets: ["Wasmtime"]
        ),
    ],
    targets: [
        .target(
            name: "CWasmtime",
            publicHeadersPath: "include"
        ),
        .target(
            name: "Wasmtime",
            dependencies: ["CWasmtime"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ],
            linkerSettings: [
                .unsafeFlags(["-L", wasmtimeLibraryPath]),
                .linkedLibrary("wasmtime"),
                .linkedLibrary("pthread", .when(platforms: [.linux])),
                .linkedLibrary("dl", .when(platforms: [.linux])),
                .linkedLibrary("m", .when(platforms: [.linux])),
            ]
        ),
        .testTarget(
            name: "WasmtimeTests",
            dependencies: ["Wasmtime", "CWasmtime"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
