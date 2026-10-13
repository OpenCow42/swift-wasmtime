# Wasmtime 48 filesystem permission migration

Wasmtime 48 replaces independent directory/file permission masks with one policy
for the entire preopened filesystem. `swift-wasmtime` exposes this directly:

```swift
try wasi.preopenDirectory(
    hostPath: path,
    guestPath: "/sandbox",
    filesystemPermissions: .readOnly
)

let directory = WasiPreopenedDirectory(
    hostPath: path,
    guestPath: "/sandbox",
    filesystemPermissions: .readWrite
)
```

`readOnly` allows reads and metadata queries but rejects mutations.
`readWrite` permits reads and mutations within the preopened directory, never
access above it. Choose write access only when the application intends it.

## Existing callers

The old Swift types, overloads, defaults, and raw flag values remain available.

| Legacy directory permissions | Legacy file permissions | Result |
| --- | --- | --- |
| `[.read]` | `[.read]` | `.readOnly` |
| `[.read, .write]` | `[.read, .write]` | `.readWrite` |
| Mixed, empty, write-only, or unknown masks | Any unrepresentable pair | `WasmtimeError.wasiConfigurationFailed` before access is granted |

This is a behavioral migration for applications using independent permissions.
For example, writable directories with read-only files cannot be represented by
the upstream 48 runtime. The adapter does not approximate them by granting file
writes or silently discarding directory access. Reusable `WasiOptions` applies
the same checks when creating its configuration.

Applications exposing separate directory/file write switches may retain their
existing calls when both switches agree. If the switches differ, handle the
configuration error or deliberately migrate to a single filesystem policy.
Do not automatically combine the switches with OR: that can broaden access.

The release retains read-only mutation regression checks, read-write operation
checks, and explicit rejection coverage for unrepresentable legacy masks.
