# Manifesto

Swift Wasmtime should feel like Swift without pretending the C API is something
it is not.

Wasmtime already has a carefully designed ownership and aliasing model. This
package preserves that model in Swift:

- Compiled modules and engines are reusable and safe to move.
- Stores own runtime state and are the boundary for values, instances, and
  functions.
- Function calls mutate store context, so the synchronous API is the honest v1
  surface.
- Async/await should arrive only when backed by Wasmtime async support or by an
  actor-owned execution context that serializes mutable access.

The project values:

- clear ownership over clever abstractions
- explicit errors over process aborts wherever the C API allows it
- readable tests over opaque binary fixtures
- vendored, verified artifacts over build-time network access
- modern Swift concurrency annotations where they are sound
- SwiftPM-friendly release tags that mirror vendored Wasmtime semver without a
  leading `v`

The first milestone is not a complete Wasmtime binding. It is a small, reliable
core that can compile, instantiate, call, trap, configure WASI, and teach future
contributors where the sharp edges are.
