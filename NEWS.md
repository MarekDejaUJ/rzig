# rzig 0.1.0

## Package authoring

- `use_rzig()` scaffolds a portable Zig-backed R package, including generated
  registration, build configuration, and a working native example.
- `document()` derives R wrappers, exports, and documentation from plain Zig
  functions marked with `/// @export`.
- Generated packages build on Linux, macOS, and Windows with Zig 0.16.0 and R's
  platform toolchain.

## Native interface

- Typed conversions cover numeric, integer, logical, optional, string, vector,
  list, matrix, attributed, and explicitly mutable values.
- Mutable numeric inputs follow R copy-on-modify semantics by duplicating before
  Zig receives writable storage.
- Long computations can check R interrupts, and pure Zig indexed loops can use
  capability-restricted worker threads.

## Reliability

- Native errors and ReleaseSafe panics become R conditions after Zig cleanup
  has completed.
- The boundary protects R allocations, keeps borrowed inputs read-only, and
  confines R API access to the calling thread.
- Cross-platform checks include hostile-input tests, garbage-collection stress,
  valgrind, native interface analysis, and reproducible boundary benchmarks.

## Documentation

- Added a worked package tutorial and a vignette showing how to port an Rcpp
  hot loop while preserving copy-on-modify, error, and interrupt behavior.
