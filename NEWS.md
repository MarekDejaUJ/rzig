# rzig 0.39.0

## New features

- `configure` compiles for the macOS version that R links for
  (`MACOSX_DEPLOYMENT_TARGET`, otherwise the minimum version of
  `libR.dylib`) in place of a fixed macOS 13.0, for Linux with musl
  (Alpine) as well as glibc, and for Windows on arm64 (from the name of R's
  compiler). `RZIG_ZIG_TARGET` overrides the detected target.
- CI cross-compiles the framework for these targets with Zig 0.16 and 0.17,
  and a canary job builds with Zig's development version without failing
  the workflow.

# rzig 0.38.0

## New features

- C-callable functions between packages: a package lists functions with
  `callconv(.c)` in `pub const rzig_callables` of its root Zig file, which
  rzig registers with `R_RegisterCCallable()` when the package loads,
  together with `rzig_interface_version` when it is declared.
  `rzig.callable(ctx, F, package, name, .{ .interface = n })` loads the
  namespace of the providing package, fetches the function with
  `R_GetCCallable()` and checks the interface version.
- The generated manifest names the R package (`pub const package`);
  `document()` regenerates it.

# rzig 0.37.0

## New features

- Zig modules shared between packages: `use_rzig_module()` creates
  `inst/zig/<module>/root.zig` in the providing package, and
  `use_rzig_import()` adds `<package>/<module>` to `Config/rzig/imports` and
  the package to `LinkingTo`. `configure` resolves the module in the
  installed package with the new `src/rzig/tools/imports.R` and passes it to
  `zig build`; the importing package compiles it, so the packages share no
  code at run time. `use_rzig_module()` also writes
  `inst/include/<package>_rzig.h`, because R CMD check expects a package in
  `LinkingTo` to provide an `include` folder. The checks before compilation
  report imports that do not resolve, packages that `LinkingTo` does not
  list, and providers without an `include` folder.

## Bug fixes

- `test_zig()` failed with Zig 0.17, whose `zig build` has no
  `--global-cache-dir`; the global cache is now set with
  `ZIG_GLOBAL_CACHE_DIR`.

# rzig 0.36.0

## New features

- Vendored C libraries: `src/rzig/c_libraries.zon` lists C libraries whose
  sources the package ships; the template `build.zig` compiles them with Zig
  and turns each header into a Zig module (`@import("name")`) with
  translate-c, which works with Zig 0.16 and 0.17 (Zig 0.17 has no
  `@cImport`). Nothing is downloaded. `use_rzig()` writes the empty list,
  `update_rzig()` adds it when missing and never replaces it, and
  `rzig_status()` reports listed files that do not exist.

# rzig 0.35.0

## New features

- Packages with C, C++ or Fortran sources: `use_rzig(path, mixed = TRUE)` and
  `use_rzig_mixed(path)` set `Config/rzig/mixed: true`, so that R compiles the
  sources of `src/` with its own compilers next to the Zig library. The
  package's own `R_init_<pkg>` registers its routines with `rzig_register()`,
  which adds the Zig routines; the checks before compilation report a mixed
  package whose sources do not call it.
- `use_rzig()` without `mixed = TRUE` names `use_rzig_mixed()` when `src/`
  holds other sources.

# rzig 0.34.0

## New features

- `rzig.Function` receives an R function, and `f.call(ctx, T, args)` calls it
  from Zig with positional or named arguments and converts the result to `T`.
  An R error, an interrupt, or the exit of a condition handler or a restart
  outside the call returns `rzig.Error`; after the Zig frames have returned,
  R continues the error or the exit unchanged, so conditions keep their class
  and call and handlers outside the call run. Queued warnings come first, R's
  random-number state passes to R and back, and R functions may call rzig
  packages again.
- The objectives and integrands of `rzig.Optimize` and `rzig.Integrate` may
  call R functions; an R error of the routines themselves now reaches R as it
  is, without an additional rzig error.
- `src/entry.c` contains `rzig_unwind_run()`, which stops R's jumps with
  `setjmp()`; `update_rzig()` replaces an unmodified `entry.c`.

# rzig 0.33.0

## New features

- `rzig.parallelReduce()` reduces over indices on worker threads in chunks
  fixed by the count alone, so the result (also a floating-point sum) is the
  same for every number of threads.
- `ctx.rngStreams()` gives random streams for workers, seeded from R's
  stream: index `i` always gets the same stream (`stream(i)`, with
  `uniform()`, `normal()`, `exponential()`), so parallel draws follow
  `set.seed()` and not the number of threads.
- A user interrupt while `parallelFor` runs stops the workers after their
  current index and is delivered as an R interrupt.

## Bug fixes

- A panic on a worker thread (for example a failed bounds check) used to call
  R from that thread, which could crash the session. The worker now records
  the message and ends, and the call raises it as an R error.

# rzig 0.32.0

## New features

- `rzig.Optimize.minimize()` runs the optimizers of `optim()` (BFGS,
  Nelder-Mead, conjugate gradients, L-BFGS-B with bounds) on Zig objectives,
  with an optional analytic gradient and otherwise the central differences of
  `optim()`; the results and counts match `optim()`.
- `rzig.Integrate.integrate()` integrates a Zig function as `integrate()`
  does, on finite and infinite ranges, with QUADPACK's failures as errors.
- Errors in objectives and integrands are recorded and reported when the
  routine finishes; the routines run guarded against R errors.

# rzig 0.31.0

## New features

- `rzig.CscMatrix` borrows a `Matrix::dgCMatrix` through its slots `i`, `p`
  and `x` and its dimensions; every index is checked on arrival (columns in
  order, rows inside the matrix and increasing within a column), so
  `column(j)` reads it without further checks. Other sparse classes are
  rejected with the `as()` call that converts them.

# rzig 0.30.0

## New features

- `rzig.Blas` (`gemm`, `gemv`, `syrk`, `trsm`) and `rzig.Lapack` (`potrf`,
  `potrs`, `getrf`, `getrs`, `gesv`, `geqrf`, `ormqr`, `gels`, `syevr`,
  `gesdd`) call R's BLAS and LAPACK with the shapes checked before each
  call, the call guarded, Fortran's hidden string lengths passed, and
  LAPACK's `info` turned into R errors. `ctx.matrix(nrow, ncol)` allocates a
  zero-filled `rzig.MutableMatrix`, and `view()` gives a read-only view.
- `use_rzig_lapack()` sets `Config/rzig/lapack: true`, and the generated
  `configure` then links `$(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)`;
  `rzig_status()` notes Zig code that calls them without it.

# rzig 0.29.0

## New features

- `rzig.Rmath.density()`, `rzig.Rmath.cdf()` and `rzig.Rmath.quantile()`
  evaluate the d, p and q functions of R for 17 distributions
  (`rzig.Distribution`), with R's parameter names and defaults
  (`rzig.Rmath.Params(.gamma)` is `.{ .shape, .scale = 1 }`), the tail and
  log options, and a guard that keeps an R warning turned into an error from
  jumping out of Zig code.
- `rng.draw(distribution, params)` draws with R's generator for the
  distribution, so draws match R's for the same seed.

# rzig 0.28.0

## New features

- Classes: a struct marked `/// @class` becomes an R class. `init` is the
  constructor, exported under the struct's name (its arguments take
  `/// @default`), and each public function whose first parameter is the
  struct is a method, called as `x$method(...)`. `document()` generates the
  `$`, `print` and `.DollarNames` methods, registers them in `NAMESPACE` (or
  through roxygen2 tags), and writes a help page with a Methods section.
  Methods may take `ctx: *rzig.Ctx` after the receiver. The objects are
  `rzig.External` values, so `deinit` runs when R collects them.

# rzig 0.27.0

## New features

- `rzig.External(T)` keeps a Zig value in an R external pointer across
  calls: `rzig.External(T).create(ctx, value)` returns a new one, inputs
  give the value through `.ptr`, and R's garbage collector runs `deinit` and
  releases the memory. The tag of the external pointer identifies the type
  and the package, so other objects are rejected without reading their
  memory; a value lost by saving and restoring is a clear error; a value
  created in a call that fails is released by the call.

# rzig 0.26.0

## New features

- `rzig.Sexp` has read-only methods: `kind()` (an `rzig.SexpKind`),
  `length()`, `isNull()`, `isObject()`, `isS4()`, `inherits()`,
  `attribute()` (S4 slots are attributes), `names()` and `classes()`
  (copied into the call context), `element()` and `field()` for lists, and
  `get(T, ctx)`, which converts the value by the rules of a parameter of
  type `T`.

# rzig 0.25.0

## New features

- `rzig.Record(T)` reads a named list into the fields of the struct `T` by
  name (defaults fill missing entries, optional fields become `null`,
  unknown entries give a warning) and builds a named list from it as a
  result. A record carries any number of values in one argument.
- `rzig.DataFrame(T)` reads the columns of a data frame into a struct of
  slices and factors, with its number of rows in `.nrow`, and builds a data
  frame with compact row names as a result.
- `rzig.Factor` reads a factor (borrowed codes, copied levels) and returns
  one; codes outside the levels are errors.
- `?T` accepts `NULL` for every input type `T`, not only scalars.

# rzig 0.24.0

## New features

- `i64` and `[]const i64` read `bit64::integer64` values (the 64-bit integers
  stored in the bits of a double vector of class `integer64`), and `i64`
  also accepts integers and whole doubles up to 2^53 - 1 in absolute value.
  `?i64` maps NA and NULL to `null`; `rzig.NA.integer64` is the missing
  value. `i64` and `[]i64` return `integer64` vectors.
- Counts and indices of long vectors (beyond 2^31 - 1) reach Zig as `i64`;
  `usize` keeps the range of R's integers, and its error message points to
  `i64`.

## Behavior changes

- `f64`, `i32`, `usize`, `[]const f64` and `rzig.Mut([]f64)` reject
  `bit64::integer64` values, whose bits are not doubles, instead of reading
  them as wrong numbers.

# rzig 0.23.0

## New features

- `rzig.Complex` (fields `re`, `im`; the layout of R's `Rcomplex`) is a
  complex scalar, and `[]const rzig.Complex` borrows a complex vector;
  `toStd()` and `fromStd()` convert to and from `std.math.Complex(f64)` for
  complex arithmetic. Both are also return types.
- `rzig.Raw` holds the bytes of a raw vector in `.data`, borrowed as an
  input and copied as a result; `[]const u8` remains a UTF-8 string.

## Repository checks

- The scripts that copy the framework into the fixture, the example and
  `inst/zig` take the list of files from `src/`, so a new framework file
  reaches client packages.
- The scaffold check follows the documented starter example (0.8.0) and the
  roxygen2 mode of `document()` (0.6.0); the fixture documents all its
  exports, so its `R CMD check` has no missing-documentation warning.

# rzig 0.22.0

## New features

- `[]const rzig.Logical` borrows a logical vector that can contain `NA`;
  `rzig.Logical` has the values `.TRUE`, `.FALSE` and `.NA` and the methods
  `isTrue()`, `isFalse()`, `isNa()` and `fromBool()`. `[]rzig.Logical` returns
  a logical vector with `NA`.
- `[]const ?[]const u8` copies a character vector in which `NA` becomes
  `null`, and `[]?[]const u8` returns one in which `null` becomes `NA`.
  `?[]const u8` accepts one string, `NA` or `NULL`.
- `rzig.NA.real`, `rzig.NA.integer` and `rzig.NA.logical` are R's missing
  values, for results that contain `NA`.

## Bug fixes

- Types written with a space before `rzig.`, such as `[]const rzig.Logical`,
  are recognized by the checks before compilation, and the printed export
  descriptions of `scan_exports()` name `rzig.Mut(rzig.Matrix)` and the
  other new types instead of calling them unsupported.

# rzig 0.21.0

## New features

- `rzig.IntMatrix` borrows an integer matrix and `rzig.BoolMatrix` copies a
  logical matrix without `NA`; with `rzig.Matrix` they are views made by
  `rzig.MatrixOf(T)` with `at(row, column)` and `column(j)`.
- `rzig.Mut([]i32)`, `rzig.Mut(rzig.Matrix)` and `rzig.Mut(rzig.IntMatrix)`
  duplicate an integer vector or a matrix before writable access; the
  duplicate keeps `dim`, `dimnames` and `class` and is what the R function
  returns. Writable matrix views add `set(row, column, value)`.
- `rzig.Attributed(T)` gains `setMatrix(nrow, ncol)` and
  `setDimnames(row_names, column_names)`, checked against the dimensions
  before R allocates the result.
- Matrices of the wrong storage mode are rejected with the `storage.mode()`
  call that converts them.

# rzig 0.20.0

## New features

- `ctx.print()` and `ctx.eprint()` write formatted text to R's output and
  message streams through `Rprintf` and `REprintf`, inside `R_ToplevelExec`,
  so a user interrupt noticed while printing becomes an R interrupt after Zig
  cleanup. Text of any length is written in full.
- `ctx.progress(total, show)` returns an `rzig.Progress` bar on R's message
  stream that redraws when its percentage changes and checks for a user
  interrupt at each redraw. A progress bar in the state of `rzig.parallelFor`
  workers is a compile error.

# rzig 0.19.0

## New features

- The generated `configure` downloads Zig when no supported compiler is
  found and `RZIG_DOWNLOAD_ZIG=true`: the verified archive of
  `install_zig()` (Zig 0.16.0, or `RZIG_ZIG_VERSION`), kept in `zig_home()`
  for later installations. Without the variable nothing is downloaded, and
  the message for a missing compiler names the variable.

# rzig 0.18.0

## New features

- `install_zig()` downloads a Zig release (0.16.0 by default, or 0.17.0) for
  the current platform into `zig_home()`, rzig's user cache folder or the
  folder named by `RZIG_ZIG_HOME`. The archive is verified against the size
  and SHA-256 published in ziglang.org's download index and pinned in rzig,
  and is fetched from a community mirror of Zig or from ziglang.org; an
  archive that differs is deleted before anything is extracted or run.
  `uninstall_zig()` removes the installations.
- `find_zig()` and the generated `configure` scripts search `zig_home()`
  after the `PATH`, so a compiler from `install_zig()` builds rzig packages
  without further setup. Their messages for a missing compiler name
  `install_zig()`.
- New packages contain `src/rzig/tools/fetch_zig.R`, the downloader that
  `install_zig()` runs; `update_rzig()` adds it to existing packages.

# rzig 0.17.0

## New features

- `RZIG_OPTIMIZE=Debug` in the environment of `R CMD INSTALL`, or
  `build_zig(optimize = "Debug")`, builds the Zig code without optimization
  and with the safety checks and complete stack traces of Zig's Debug mode.
  `ReleaseSafe` stays the default; `ReleaseFast` and `ReleaseSmall` are
  rejected with a message, because the boundary turns failed safety checks
  into R errors. The printed build result names a Debug build.

# rzig 0.16.1

## Repository checks

- The SIGINT integration check creates its readiness marker inside the
  `tryCatch()` that handles the interrupt, so a signal that arrives before
  the Zig loop starts is still caught on a busy machine.

# rzig 0.16.0

## New features

- `create_rzig_package()` creates a new package in one call: a
  `DESCRIPTION` (GPL-3, `SystemRequirements: Zig 0.16.x or 0.17.x`, fields
  replaceable through `fields`), the scaffold of `use_rzig()` with the
  `hello_zig()` example and its help page, a testthat suite with one test,
  and optionally the workflow of `use_rzig_ci()`. The created package passes
  `R CMD check --as-cran`.

# rzig 0.15.0

## New features

- `use_rzig_ci()` writes a GitHub Actions workflow
  (`.github/workflows/rzig-check.yaml`) that installs R and Zig and runs
  `R CMD check --as-cran` for each operating system and Zig version of its
  matrix (Linux, macOS and Windows; Zig 0.16.0 and 0.17.0 by default), with
  the Zig tests of `src/rzig/src/tests.zig` first when that file exists.

# rzig 0.14.0

## New features

- `test_zig()` runs the Zig tests of a package (`zig build test`) on the host
  without R: the `test` blocks of the files imported by
  `src/rzig/src/tests.zig`. The package folder receives no build output, the
  Zig cache is kept for the session, and failed tests are listed by name.
- The `build.zig` template has a `test` step for `test_zig()`;
  `update_rzig()` installs it in packages with an unmodified older
  `build.zig`.

# rzig 0.13.0

## Behavior changes

- Errors of the boundary name the R argument: "argument `a` of add_vectors
  must be a numeric vector; got integer; use as.numeric() in R" instead of
  "`argument 1 of add_vectors` must be ...". The names come from the
  manifest; a hand-written manifest without parameter names keeps the
  position.
- The compile error for more than 32 arguments suggests passing related
  values together as one vector or matrix instead of a list argument, which
  the boundary does not accept.

# rzig 0.12.0

## New features

- Export options on the marker line: `/// @export name=<R name>` gives the R
  wrapper a name other than the Zig name, and `/// @export invisible` makes
  it return its value invisibly; the options combine with `internal`.
- `/// @default <argument> <R expression>` gives an argument of the wrapper a
  default value; the expression must parse and the argument must exist.
  The help pages show the defaults in their usage.

# rzig 0.11.0

## New features

- `zig_function()` compiles Zig code from the R prompt into a package in the
  session's temporary directory and defines its exported functions, the
  counterpart of `Rcpp::cppFunction()`; `zig_source()` does the same for a
  file and `zig_eval()` evaluates one expression of a given type. The
  header (`std`, `builtin`, `rzig`, the panic handler) and the registration
  block are added when the code lacks them, every `pub fn` is exported when
  the code marks none with `/// @export`, builds are cached for the session,
  and a compiler error is reported with the line of the code.
- A knitr engine `zig` (`eng_zig()`, registered when knitr loads) compiles a
  chunk with `zig_function()`, so later R chunks call its functions.

# rzig 0.10.1

## Continuous integration

- A CRAN-style check of a newly generated client package runs on Linux,
  macOS and Windows with both Zig series (`tools/check_client_package.R`):
  `R CMD check --as-cran` with two cores, the CPU-to-elapsed threshold of the
  installation and a separate temporary directory, failing on any NOTE.
- A reverse-dependency job updates pnsbib from GitHub with `update_rzig()`,
  builds it and runs its native and R tests (`tools/check_reverse_pnsbib.sh`).
- The R-devel job compares the R entry points the framework declares with
  `tools:::nonAPI` and `tools:::funAPI()` (`tools/check_api_symbols.R`).
- `rzig_status()` of the example package must report every structural check
  ok, and the example lists its Zig sources for `devtools::load_all()`.

# rzig 0.10.0

## New features

- The environment variable `RZIG_ZIG_CACHE` names a persistent global Zig
  cache for the builds of client packages. Without it, each installation
  starts with an empty cache inside the package, which keeps `R CMD check`
  clean but lets Zig 0.17 compile its build runner again for every
  installation; with it, a repeated build of the starter package takes about
  15 seconds instead of minutes on a loaded machine.

# rzig 0.9.1

## Tests

- The integration check that sends a real SIGINT waits until R has entered
  the interruptible loop (R creates a marker file just before it), instead
  of sending the signal after a fixed 0.3 seconds, which a loaded machine
  could exceed before R started the loop.

# rzig 0.9.0

## New features

- Exports in several files: the scan follows `pub const name =
  @import("file.zig");` declarations of `main.zig` (recursively) and finds
  the `/// @export` functions of those files, registered as `name.function`.
  `/// @export` above `pub const twice = other.twice;` re-exports a function
  of an imported file. Before, markers outside `main.zig` were ignored
  without a message.
- A marker in a file imported with a plain `const`, which the generated
  registration cannot reach, is an error that says how to import the file;
  a marked file that is not imported is noted by `rzig_status()`, and an R
  name exported twice is an error naming both places.
- `scan_exports()` records the `file` of each export and the `files`
  scanned; `print()` shows the file of exports outside `main.zig`, and
  `build_zig()` attributes compiler errors in any of these files to their
  exported function.

# rzig 0.8.0

## New features

- `document()` writes a help page `man/<name>.Rd` for every exported Zig
  function of a package that does not use roxygen2, from the function's doc
  comment: the first paragraph is the title and description, and `@param`,
  `@return`, `@examples`, `@details`, `@seealso`, `@references` and `@note`
  fill their sections; `code` spans become `\code{}`. Pages rzig wrote for
  functions that are gone are removed, and pages of other origin are left
  alone. In roxygen-managed packages roxygen2 writes the pages, and rzig
  removes its own.
- The starter `hello_zig()` documents its parameter and return value and has
  an example, so a new scaffold passes `R CMD check` without the
  "Undocumented code objects" and "No examples, no tests, no vignettes"
  warnings.
- `rzig_status()` reports help pages that no longer match the doc comments.

# rzig 0.7.0

## New features

- `rzig.parallelFor()` limits its worker threads: `RZIG_NUM_THREADS` lowers
  the number (an invalid value is an error naming the variable),
  `OMP_THREAD_LIMIT` is respected, and while `R CMD check` limits the cores
  (`_R_CHECK_LIMIT_CORES_`, as in CRAN submission checks) at most two threads
  run. Before, a call used one thread per core up to 32 in any setting.
- `rzig.parallelThreadCount(count)` returns the number of worker threads a
  call of `parallelFor` with `count` indices uses.

# rzig 0.6.0

## New features

- Packages whose `NAMESPACE` roxygen2 generates: `document()` writes the
  `useDynLib` directive of the native routines into `R/rzig-wrappers.R` as a
  `@rawNamespace` tag and adds the lines roxygen2 writes from the tags to
  `NAMESPACE`, instead of a block that `roxygen2::roxygenise()` removed. The
  package works whichever of `rzig::document()`, `roxygenise()` or
  `devtools::document()` ran last; before, a call of `roxygenise()` after
  `document()` left `.Call()` without its native symbols ("object
  'hello_zig_' not found"), which `R CMD check` reported only as a NOTE.
- `render_bindings()` takes `roxygen`, and `rzig_status()` checks the
  bindings of both kinds of packages.

# rzig 0.5.0

## New features

- A doc line `/// @export internal` marks a native routine that only the
  package's own R code calls: it is registered and gets an R wrapper and a
  native symbol (`<name>_`), but the wrapper is not exported from the package
  and gets no help page. Packages no longer need to patch the generated
  manifest and `NAMESPACE` for such routines.
- Only `/// @export` and `/// @export internal` are accepted; any other
  option, or a second `@export` line above one function, is an error of the
  scan with the file and line.
- `scan_exports()` records `internal`, `as.data.frame()` shows it, and
  subsetting the result (`exports[1:2]`) keeps its class.

# rzig 0.4.0

## New features

- `update_rzig()` brings a package to the installed version of rzig: it
  replaces the framework sources, updates every build file that is still an
  unmodified template of some rzig version (recognized by the MD5 sums of all
  templates rzig has shipped), adds missing build files, removes the Zig
  scanner that rzig 0.2 copied into `src/rzig/tools/`, and regenerates the
  bindings. Build files the package author changed are kept and listed;
  `force = TRUE` replaces them. The package author's Zig sources and files
  rzig does not know are never changed or removed.
- `rzig_status(build = TRUE)` takes `lib`, the library `build_zig()` installs
  into.

## Behavior changes

- `use_rzig(overwrite = TRUE)` no longer deletes the files under `src/rzig`
  that rzig does not know, and stops before changing anything when a build
  file differs from every rzig template; `force = TRUE` replaces such files.
  Before, it replaced customized build files and removed other files without
  a message.
- `rzig_status()` recommends `update_rzig()` for framework sources from
  another rzig version.

# rzig 0.3.9

## Bug fixes

- `use_rzig()` stops with an explanation when the package already has a
  hand-written `src/Makevars` or `src/Makevars.win` (which `configure` would
  overwrite and `cleanup` would remove, so that its settings silently
  disappeared from the built package) or C, C++ or Fortran sources in `src/`
  (which the generated Makevars do not compile).
- `rzig_status()` reports such sources and Makevars files in the Scaffold
  check. A source whose object file a customized `src/Makevars.in` lists
  counts as handled.
- `document()` removes a `useDynLib(<pkg>, .registration = TRUE, .fixes =
  "C_")` line only when the old wrapper file shows that rzig 0.1 wrote it; a
  package author's own directive stays in `NAMESPACE`.

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
