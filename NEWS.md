# rzig 0.3.8

## Tests

- The hostile-input suite (`tests/abuse.R` and the test package) passes S4
  objects, an S4 class whose data part is a double vector, classed vectors
  (a units-like class and `Date`) and a data frame to every typed parameter
  and checks that each call ends in an R error naming the argument or
  converts the data part, and that `rzig.Sexp` returns the S4 object
  unchanged.

# rzig 0.3.7

## Bug fixes

- Printing a column subset of a `rzig_status` object (for example
  `status[, c("step", "ok")]`) shows the data frame instead of failing with
  "non-character argument".
- `build_zig()` reports a duplicate-symbol error of the linker (`duplicate
  symbol`, `multiple definition of`) at the link step instead of the
  install step.

# rzig 0.3.6

## Compiler search

- Without `ZIG`, `find_zig()` and the generated `configure` use the first
  compiler of a supported release series among the `PATH` and the usual
  install locations (`~/.local/share/zig/*/zig`, `~/zig/zig`), so an old
  `zig` on the `PATH` no longer hides a supported one. When none is
  supported, the first compiler found is reported with the reason, and
  `find_zig()` lists the others. An explicit `ZIG` is used as given.
- Development builds of Zig (for example `0.17.0-dev.12+abcdef`) are
  rejected with a message saying so: their language and standard library can
  differ from the release of the same series.

# rzig 0.3.5

## Build files

- The generated Makevars compile `src/entry.c` with R's compiler flags
  (`$(ALL_CFLAGS)`), so the flags of the R installation and of CRAN's check
  configurations reach it; the fixed `-O2 -Wall -pedantic` is gone.
- `zig build` runs with `-j2`, within CRAN's limit of two cores during
  checks.
- `configure` asks R for its include directory (`R.home("include")`), which
  Linux distributions can place outside `R_HOME`, and falls back to
  `R_HOME/include`.
- The macOS repack script points `TMPDIR` at its own temporary directory, so
  a cache written by the Apple tool shims (`xcrun_db`) is removed with it and
  does not appear as detritus in `R CMD check`.

# rzig 0.3.4

## Documentation

- The help pages render their Markdown: `DESCRIPTION` declares
  `Roxygen: list(markdown = TRUE)`, so links between the step functions, the
  bullet lists of `?rzig_status` and code spans appear as intended instead
  of as literal `[build_zig()]`, `**DESCRIPTION**` and backticks.

# rzig 0.3.3

## Bug fixes

- Reinstalling a client package from its source folder (`R CMD INSTALL`,
  `install.packages(path, repos = NULL)`, the RStudio Install button)
  rebuilt the Zig library only when `build.zig`, `build.zig.zon` or
  `main.zig` changed, so an edit of any other Zig file, or of the framework,
  left the old native code in the package. The generated Makevars now runs
  `zig build` on every installation; Zig's cache keeps an unchanged build
  fast.
- `use_rzig()` lists the Zig sources in the `Config/build/extra-sources`
  field of `DESCRIPTION` (keeping entries the package author listed), so
  `devtools::load_all()` recompiles after a change to a Zig file instead of
  loading the old shared object.
- `rzig_status()` notes a `DESCRIPTION` whose `SystemRequirements` does not
  name Zig or whose `Config/build/extra-sources` does not list the Zig
  sources. A `DESCRIPTION` without a `Version` field no longer stops the
  check with "subscript out of bounds".

# rzig 0.3.2

## Bug fixes

- `rzig_status()` compares only the framework sources under
  `src/rzig/framework` with the installed rzig. `build.zig`, `build.zig.zon`
  and `src/rzig/tools/` are templates a package may extend, like `configure`
  and the Makevars, so a difference is a note and no longer fails the
  Scaffold check; `build_zig()` therefore builds packages with customized
  build files. A missing build file still fails the check. `src/entry.c` is
  compared with its template after the package name is substituted.

# rzig 0.3.1

## Bug fixes

- The generated `.Call` wrappers are no longer symbols of the client
  package's shared object. Each wrapper was exported under the R name of its
  function, so an export named like a C library function (`exp`, `log`,
  `free`) replaced that function inside the package and crashed R at the
  first call. The wrappers are reached through the registration table only,
  and `rzig_init` has hidden visibility; the shared object exports only
  `R_init_<pkg>` and `R_unload_<pkg>`.
- `rzig_status()` notes an export that masks a function of base R or of the
  attached base packages, for example `log`.

# rzig 0.3.0

## Step-wise workflow

- New functions expose each step of the workflow: `find_zig()` locates a
  supported Zig compiler, `scan_exports()` lists the exported Zig functions
  with their R arguments and the R values of every parameter and return type,
  `render_bindings()` shows the generated manifest, R wrappers and `NAMESPACE`
  block, and `rzig_status()` reports which steps of a package are complete
  and whether the generated bindings match the Zig source.
- `build_zig()` compiles and installs a package from a temporary copy, keeps
  the complete installation log, and reports the errors of the Zig compiler,
  the C compiler, the linker and the load test with their files and lines,
  and the exported function concerned.
- `rzig_status()` checks, before compilation, argument and return types the
  boundary rejects, more than 32 arguments, misuse of `rzig.Mut([]f64)`,
  error sets other than `rzig.Error`, the registration block and panic
  handler in `main.zig`, R functions with the name of an export, framework
  sources from another rzig version, non-executable `configure` and
  `cleanup` scripts, and the C toolchain of R. `rzig_status(build = TRUE)`
  adds the result of `build_zig()`.
- `use_rzig(overwrite = TRUE)` updates the framework sources and build files
  and keeps the package author's Zig sources in `src/rzig/src`. It adds the
  Zig build caches to `.Rbuildignore`.
- `use_rzig()` and `document()` return printable objects describing the files
  written and the exports found.
- The export scan runs in R. `use_rzig()`, `scan_exports()`,
  `render_bindings()` and `document()` need no Zig compiler; Zig is required
  only to install a package created with the scaffold. The package examples
  run on CRAN, and the vignette executes the generation steps.
- The Zig scanner is no longer copied into client packages.

## Zig version policy

- rzig supports the Zig 0.16 and 0.17 release series. `find_zig()` and the
  generated `configure` scripts accept versions `0.16.x` and `0.17.x` and
  reject other series with a message naming the found version, because Zig
  changes its language and standard library between release series. The
  framework reads the type descriptions of both compilers and sets the Zig
  cache directories through environment variables, which both compilers
  accept.

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
