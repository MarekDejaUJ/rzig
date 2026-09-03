# rzig 0.2.3

## CRAN resubmission

- Removed redundant wording from the package title and description.
- `use_rzig()` and `document()` now require an explicit package path, so
  neither function writes to the working directory by default.
- Added executable, temporary-directory examples for both exported functions;
  they use `\donttest{}` because they require the external Zig toolchain.
- `document()` now confines Zig's local cache, global cache, and compiler
  temporary files to an automatically cleaned R session temporary directory.

# rzig 0.2.2

## CRAN submission

- Updated the maintainer contact and added the author's ORCID identifier.

# rzig 0.2.1

## Package authoring

- `use_rzig()` now scaffolds `cleanup` and `cleanup.win`, preventing generated
  Makevars and Zig build caches from entering source-package checks.
- `document()` uses the same Zig discovery order as package configuration and
  rejects unsupported compiler versions before running the export scanner.
- The onboarding guide now edits the generated example in place, documents the
  complete parameter and return surface, and explains warning and roxygen2
  workflows.

# rzig 0.2.0

## Statistical interface breadth

- Integer, logical, and character vectors can be returned directly, decorated
  with attributes, and placed in generated lists.
- `Ctx.rng()` provides boundary-managed draws from R's random-number stream,
  preserving `set.seed()` reproducibility on success and error paths.
- `Rmath.normalCdf()` and `Rmath.normalQuantile()` expose the linked R
  runtime's normal distribution functions without consuming random state.

## Boundary behavior

- User interrupts retain R's `interrupt` condition class after Zig cleanup;
  ordinary error handlers and `try()` no longer swallow Ctrl-C.
- The POSIX integration gate sends a real `SIGINT`, checks the condition class,
  and verifies that the R session remains usable.
- The causal demonstration now returns a logical adjacency matrix and covers
  all three-variable orders plus a 12-variable search through depth five.

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
