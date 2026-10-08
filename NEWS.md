# rzig 0.3.0

## Step-wise workflow

- New functions expose each step of the workflow: `find_zig()` locates a
  supported Zig compiler, `scan_exports()` lists the exported Zig functions
  with their R arguments and the R values of every parameter and return type,
  `render_bindings()` shows the generated manifest, R wrappers and `NAMESPACE`
  block, and `rzig_status()` reports which steps of a package are complete
  and whether the generated bindings match the Zig source.
- `use_rzig()` and `document()` return printable objects describing the files
  written and the exports found.
- The export scan runs in R. `use_rzig()`, `scan_exports()`,
  `render_bindings()` and `document()` need no Zig compiler; Zig is required
  only to install a package created with the scaffold. The package examples
  run on CRAN, and the vignette executes the generation steps.
- The Zig scanner is no longer copied into client packages.

## Zig version policy

- rzig supports the Zig 0.16 release series. `find_zig()` and the generated
  `configure` scripts accept versions `0.16.x` and reject other series with a
  message naming the found version, because Zig changes its language and
  standard library between minor releases.

## Portability

- The generated `src/entry.c` includes no R header. R installations whose
  headers lack `R_ext/Visibility.h`, such as the Debian and Ubuntu `r-base`
  packages, can install client packages.

## Tests

- `tests/testthat` runs on CRAN: scanner fixtures, rendering, the scaffold
  and documentation workflow without Zig, and `find_zig()`. A parity test
  compares the R scan with the Zig scanner where a supported Zig is present.

## Licensing

- rzig is distributed under GPL-3. Releases up to and including 0.2.3
  remain available under the MIT license.
- The example package `rzigcausal` and the test package `rzigtest` are
  distributed under GPL-3.

# rzig 0.2.3

## CRAN resubmission

- Removed redundant wording from the package title and description.
- `use_rzig()` and `document()` now require an explicit package path, so
  neither function writes to the working directory by default.
- Added executable, temporary-directory examples for both exported functions;
  they use `\donttest{}` because they require the external Zig toolchain.
- `document()` now confines Zig's local and global caches to an automatically
  cleaned R session temporary directory. On Unix, its compiler subprocess also
  receives a private temporary directory.

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
