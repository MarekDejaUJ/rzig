# RZig

RZig lets R package authors write plain Zig functions and generate safe
`.Call` bindings without C++ or hand-written `SEXP` conversion code.

## Requirements

- R and the platform toolchain used to build R source packages: Xcode
  command-line tools on macOS, Rtools on Windows, a C compiler and the R
  development headers on Linux.
- Zig of the 0.16 or 0.17 release series (`0.16.x` or `0.17.x`), needed
  only to install a package created with RZig. RZig itself, its examples
  and its tests run without Zig. Zig changes its language and standard
  library between release series, so other versions are rejected with a
  message naming the version found.

Code that has to build with both series is best formatted with the
`zig fmt` of Zig 0.16: the formatter of Zig 0.17 rewrites `@intFromEnum`
and `@enumFromInt` into the builtins `@backingInt` and
`@fromBackingInt`, which Zig 0.16 does not have.

`configure` compiles the Zig code for the platform of R: x86_64 or arm64
macOS for the macOS version that R links for
(`MACOSX_DEPLOYMENT_TARGET`, or that of `libR.dylib`), x86_64 or arm64
Linux with glibc or musl, and x86_64 or arm64 Windows. `RZIG_ZIG_TARGET`
names another Zig target, for example
`RZIG_ZIG_TARGET=x86_64-linux-musl`.

Download Zig from <https://ziglang.org/download/> and confirm the
version:

``` sh
zig version
# 0.16.0
```

## Install RZig

From CRAN:

``` r

install.packages("rzig")
```

The development version from GitHub:

``` r

install.packages("remotes")
remotes::install_github("MarekDejaUJ/rzig")
```

If Zig is not on `PATH`, tell RZig where it is:

``` r

Sys.setenv(ZIG = "/absolute/path/to/zig")
```

[`find_zig()`](https://marekdejauj.github.io/rzig/reference/find_zig.md)
and the generated package configuration search in this order: `ZIG`,
`PATH`, `~/.local/share/zig/*/zig`, then `~/zig/zig`. An R session
launched from an IDE may not inherit variables exported by a shell; in
that case, set `ZIG` with
[`Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html) first.

``` r

rzig::find_zig(required = FALSE)
#> Zig compiler: /usr/local/bin/zig (version 0.16.0, supported)
#> rzig supports Zig 0.16.x or 0.17.x.
```

## Create a working package

The workflow has five steps, each an R function. For a copy-paste-safe
example, create the package in R’s session temporary directory. Replace
[`tempdir()`](https://rdrr.io/r/base/tempfile.html) with an explicit
project directory when keeping the result.

**1. Scaffold.**
[`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md)
adds the build files, the framework sources and a starter
`src/rzig/src/main.zig` with a working `hello_zig()` function:

``` r

pkg <- file.path(tempdir(), "rzhello")
dir.create(pkg)
writeLines(
  c(
    "Package: rzhello",
    "Type: Package",
    "Title: A Small RZig Example",
    "Version: 0.0.1",
    "Authors@R: person('Your', 'Name', email = 'you@example.org', role = c('aut', 'cre'))",
    "Description: Demonstrates a Zig implementation called safely from R.",
    "License: GPL-3",
    "Encoding: UTF-8"
  ),
  file.path(pkg, "DESCRIPTION")
)
rzig::use_rzig(pkg)
#> Generated RZig bindings for rzhello: 1 exported function
#> Created RZig scaffold for package rzhello
```

**2. Write Zig.** Open `src/rzig/src/main.zig`, keep its imports,
`panic` declaration and `comptime` registration block, and replace the
generated `hello_zig()` function with:

``` zig
/// Add two numeric vectors elementwise.
/// @param a The first numeric vector.
/// @param b The second numeric vector.
/// @return The elementwise sums.
/// @export
pub fn add_vectors(
    ctx: *rzig.Ctx,
    a: []const f64,
    b: []const f64,
) rzig.Error![]f64 {
    if (a.len != b.len) {
        return rzig.raise("lengths differ: {d} vs {d}", .{ a.len, b.len });
    }
    const result = try ctx.alloc(f64, a.len);
    for (a, b, result) |left, right, *value| value.* = left + right;
    return result;
}
```

The `@param` and `@return` lines are optional. When they are absent,
[`document()`](https://marekdejauj.github.io/rzig/reference/document.md)
generates neutral placeholders from the Zig signature. Only
`/// @export` is required to expose a public function to R. Exported
functions are top-level `pub fn` declarations starting at the beginning
of a line, as `zig fmt` writes them.

**3. Scan.**
[`scan_exports()`](https://marekdejauj.github.io/rzig/reference/scan_exports.md)
lists what R will see, with the R value of every parameter and of the
return value:

``` r

rzig::scan_exports(pkg)
#> Zig exports of package rzhello (src/rzig/src/main.zig): 1 function
#>
#> add_vectors(a, b)
#>   a          []const f64            double vector, borrowed
#>   b          []const f64            double vector, borrowed
#>   returns    rzig.Error![]f64       double vector
```

**4. Generate.**
[`document()`](https://marekdejauj.github.io/rzig/reference/document.md)
writes the Zig manifest, the R wrappers and the `NAMESPACE` block;
[`render_bindings()`](https://marekdejauj.github.io/rzig/reference/render_bindings.md)
shows the same texts without writing them, and
[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
reports whether every step is complete:

``` r

rzig::document(pkg)
#> Generated RZig bindings for rzhello: 1 exported function
rzig::rzig_status(pkg)
#> RZig status of package rzhello
#>   [ok] DESCRIPTION   package rzhello
#>   [ok] Scaffold      build files and framework sources present
#>   [ok] Zig source    src/rzig/src/main.zig
#>   [ok] Exports       1 function: add_vectors
#>   [ok] Bindings      generated files match the exports
#>   [ok] Zig compiler  /usr/local/bin/zig (version 0.16.0)
#>   [ok] C toolchain   C compiler clang
```

[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
also reports, before anything is compiled, argument and return types the
boundary rejects, more than 32 arguments, misuse of `rzig.Mut([]f64)`, a
missing registration block or panic handler in `main.zig`, R functions
of the same name elsewhere in `R/`, framework sources from another rzig
version, non-executable `configure` scripts and a missing C toolchain. A
failed build names its cause:

``` r

rzig::build_zig(pkg, preflight = FALSE)
#> Build of package rzhello: failed at the compile step
#>   src/rzig/framework/convert.zig:138:9 (function total)
#>     rzig: function `total`, parameter 1 has unsupported type '[]const f32'.
#>     nearest supported alternative: []const f64 for an R numeric vector
#> The complete installation log (61 lines) is in $log.
```

**5. Build and call.**
[`build_zig()`](https://marekdejauj.github.io/rzig/reference/build_zig.md)
runs the checks of
[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md),
compiles and installs the package from a temporary copy, and reports the
first compiler, linker or load error with its file and line when the
build fails. The package also installs like any source package, with
`install.packages(pkg, repos = NULL, type = "source")` or
`R CMD INSTALL`.

``` r

build <- rzig::build_zig(pkg)
build
#> Build of package rzhello: succeeded in 8.1 seconds
#> Zig compiler: /usr/local/bin/zig (version 0.16.0)
#> Installed into a library in the session temporary directory
library(rzhello, lib.loc = build$library)

add_vectors(c(1, 2, 3), c(10, 20, 30))
#> [1] 11 22 33

add_vectors(c(1, 2), c(1, 2, 3))
#> Error: lengths differ: 2 vs 3

# The session remains usable after the native error.
add_vectors(c(4, 5), c(6, 7))
#> [1] 10 12
```

The same workflow applies to an existing package: run
[`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md)
once, edit `src/rzig/src/main.zig`, and run
[`document()`](https://marekdejauj.github.io/rzig/reference/document.md)
whenever exported Zig signatures or comments change. The scaffolded
`cleanup` and `cleanup.win` scripts remove generated Makevars and Zig
build caches after package installation and checks.
[`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md)
stops when `src/` already holds C, C++ or Fortran sources (see the next
section for such packages) or a hand-written `src/Makevars`, whose
settings belong in `src/Makevars.in` and `src/Makevars.win.in`.

## Packages with C, C++ or Fortran sources

`use_rzig(path, mixed = TRUE)` (or `use_rzig_mixed(path)` in a package
that already uses rzig) sets `Config/rzig/mixed: true`. R then compiles
every C, C++ and Fortran source of `src/` with its own compilers and
links them with the Zig library, and `src/entry.c` leaves `R_init_<pkg>`
to the package. The package’s `R_init_<pkg>` registers its routines with
`rzig_register()`, which adds the Zig routines to the `.Call` routines:

``` c
#include <R_ext/Rdynload.h>

void rzig_register(DllInfo *dll, const R_CMethodDef *c_methods,
                   const R_CallMethodDef *call_methods,
                   const R_FortranMethodDef *fortran_methods,
                   const R_ExternalMethodDef *external_methods);

static const R_CallMethodDef call_methods[] = {
    {"legacy_add", (DL_FUNC) &legacy_add, 2},
    {NULL, NULL, 0}
};

void R_init_mypkg(DllInfo *dll) {
    rzig_register(dll, NULL, call_methods, NULL, NULL);
}
```

The R code keeps its own `useDynLib()` directive for the C routines and
may name them by symbol or by string.
[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
and
[`build_zig()`](https://marekdejauj.github.io/rzig/reference/build_zig.md)
report a mixed package whose sources do not call `rzig_register()`.

## C libraries compiled by Zig

A package can ship the sources of a C library, for example under
`src/rzig/vendor/answer`, and list it in `src/rzig/c_libraries.zon`. Zig
compiles the sources into the package and translates the header into a
Zig module; nothing is downloaded.

``` zig
.{
    .{
        .name = "answer",
        .header = "vendor/answer/answer.h",
        .sources = .{"vendor/answer/answer.c"},
        .include = .{"vendor/answer"},
        .flags = .{"-std=c99"},
    },
}
```

The Zig sources then call the library through
`const answer = @import("answer");`, also in the tests of
[`test_zig()`](https://marekdejauj.github.io/rzig/reference/test_zig.md).
Paths are relative to `src/rzig`;
[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
reports listed files that do not exist, and
[`update_rzig()`](https://marekdejauj.github.io/rzig/reference/update_rzig.md)
never replaces the file. The license and copyright of the vendored code
belong in the package’s `DESCRIPTION` and `inst/COPYRIGHTS`.

## Zig modules shared between packages

A package shares Zig code as a module:
`use_rzig_module(path, "kernels")` creates `inst/zig/kernels/root.zig`,
which R installs with the package. Another package uses it with
`use_rzig_import(path, "kernelpkg", "kernels")`, which adds
`kernelpkg/kernels` to `Config/rzig/imports` and `kernelpkg` to
`LinkingTo`, so that R installs `kernelpkg` first. Its Zig code then
imports the module:

``` zig
const kernels = @import("kernels");

/// Twice the sum of the values.
/// @export
pub fn total(x: []const f64) f64 {
    return 2 * kernels.sum(x);
}
```

`configure` finds the module in the installed package, and the module is
compiled into the importing package, so nothing is linked between
packages at run time. A module can import `rzig` and the other imported
modules;
[`test_zig()`](https://marekdejauj.github.io/rzig/reference/test_zig.md)
passes the imports to the Zig tests as well.

## C-callable functions between packages

Compiled code of other packages, in C or in Zig, can call functions that
a package registers with `R_RegisterCCallable()`. The root Zig file
lists them, each with `callconv(.c)`, and may declare an interface
version:

``` zig
fn scaledSum(x: [*]const f64, n: usize, factor: f64) callconv(.c) f64 {
    var total: f64 = 0;
    for (x[0..n]) |value| total += value;
    return factor * total;
}

pub const rzig_callables = .{ .scaled_sum = scaledSum };
pub const rzig_interface_version: u32 = 2;
```

Another rzig package fetches one with `rzig.callable()`, which loads the
namespace of the providing package and checks the interface version,
because R checks neither the signature nor a version:

``` zig
const ScaledSum = fn ([*]const f64, usize, f64) callconv(.c) f64;
const scaled_sum = try rzig.callable(ctx, ScaledSum, "provpkg", "scaled_sum", .{ .interface = 2 });
```

C code calls `R_GetCCallable("provpkg", "scaled_sum")` after loading the
namespace; the providing package can declare the C signatures in
`inst/include`. The calling package lists the providing one in
`Imports`.

## Compiling Zig from the R prompt

[`zig_function()`](https://marekdejauj.github.io/rzig/reference/zig_function.md)
compiles Zig code into a small package in the session’s temporary
directory and defines its functions, like `Rcpp::cppFunction()`:

``` r

twice <- rzig::zig_function("pub fn twice(x: f64) f64 { return 2 * x; }")
twice(21)
#> [1] 42
rzig::zig_eval("@sqrt(2.0)", type = "f64")
#> [1] 1.414214
```

`zig_source(file)` does the same for a file. Every top-level `pub fn` is
exported unless the code marks functions with `/// @export`. Builds are
cached for the session, and a compiler error is reported with the line
of the code. In R Markdown and Quarto documents, a `zig` chunk compiles
its code with
[`zig_function()`](https://marekdejauj.github.io/rzig/reference/zig_function.md)
and later R chunks can call the functions.

## Printing and progress

`ctx.print()` and `ctx.eprint()` format text with Zig’s `std.fmt` and
write it to R’s output and message streams (`Rprintf`, `REprintf`), so
it reaches the console, RStudio and
[`sink()`](https://rdrr.io/r/base/sink.html).
`ctx.progress(total, show)` draws a progress bar on the message stream
and checks for a user interrupt at each redraw:

``` zig
/// @default verbose interactive()
/// @export
pub fn simulate(ctx: *rzig.Ctx, n: usize, verbose: bool) rzig.Error!f64 {
    var progress = ctx.progress(n, verbose);
    var total: f64 = 0;
    for (0..n) |i| {
        total += @sqrt(@as(f64, @floatFromInt(i)));
        try progress.add(1);
    }
    try progress.finish();
    return total;
}
```

All three need the call context, so they run on the R thread; a progress
bar in the state of `rzig.parallelFor` workers is a compile error.

## Debugging builds

Packages build in Zig’s `ReleaseSafe` mode: optimized, with the bounds,
overflow and `unreachable` checks that the boundary turns into R errors.
`build_zig(path, optimize = "Debug")`, or `RZIG_OPTIMIZE=Debug` in the
environment of `R CMD INSTALL`, builds without optimization and with the
same checks and complete stack traces. `ReleaseFast` and `ReleaseSmall`
are rejected, because they remove the checks; `@setRuntimeSafety(false)`
removes them from a single function whose safety the package author has
established.

## Zig tests without R

`test_zig(path)` runs `zig build test` for a package: the `test` blocks
of the files that `src/rzig/src/tests.zig` imports are compiled for the
host and run without R, which suits numerical kernels written in plain
Zig:

``` zig
// src/rzig/src/tests.zig
test {
    _ = @import("kernels.zig");
}
```

Files that use the `rzig` module call into R and are tested from R
(`testthat`). Packages scaffolded by an older rzig get the `test` step
of `build.zig` from `update_rzig(path)`.

## Installing Zig

[`install_zig()`](https://marekdejauj.github.io/rzig/reference/install_zig.md)
downloads Zig 0.16.0 (or `install_zig("0.17.0")`) for the current
platform into
[`zig_home()`](https://marekdejauj.github.io/rzig/reference/install_zig.md),
a folder in rzig’s user cache. The archive is checked against the size
and SHA-256 that ziglang.org publishes, pinned in rzig, and comes from a
community mirror of Zig or from ziglang.org.
[`find_zig()`](https://marekdejauj.github.io/rzig/reference/find_zig.md)
and the `configure` scripts of rzig packages find compilers installed
there;
[`uninstall_zig()`](https://marekdejauj.github.io/rzig/reference/install_zig.md)
removes them.

## Installing rzig packages on machines without Zig

The `configure` script of a package created with rzig downloads Zig
itself when no supported compiler is found and the environment variable
`RZIG_DOWNLOAD_ZIG` is `true`:

``` r

Sys.setenv(RZIG_DOWNLOAD_ZIG = "true")
install.packages("zigstats", repos = "https://example.r-universe.dev")
```

The download is the verified archive of
[`install_zig()`](https://marekdejauj.github.io/rzig/reference/install_zig.md)
(Zig 0.16.0, or the release named by `RZIG_ZIG_VERSION`) and is kept in
[`zig_home()`](https://marekdejauj.github.io/rzig/reference/install_zig.md)
for later installations. Without the variable, nothing is downloaded and
the installation stops with instructions.

## Creating a package

`create_rzig_package("path/to/zigstats")` creates a package named
`zigstats` with the scaffold, the `hello_zig()` example, its help page
and a testthat suite; `build_zig("path/to/zigstats")` installs it.
Replace the placeholder title, description and author through `fields`:

``` r

rzig::create_rzig_package("zigstats", fields = list(
  Title = "Rank Statistics in 'Zig'",
  "Authors@R" = 'person("Ada", "Lovelace", email = "ada@example.org", role = c("aut", "cre"))'
))
```

## Continuous integration

`use_rzig_ci(path)` writes `.github/workflows/rzig-check.yaml`, a GitHub
Actions workflow that installs R and Zig 0.16.0 and 0.17.0 and runs
`R CMD check --as-cran` on Linux, macOS and Windows, after the Zig tests
when `src/rzig/src/tests.zig` exists. The `zig` and `os` arguments
choose the matrix.

## Export options

The marker line and `@default` lines shape the R wrapper:

``` zig
/// Fit the model.
/// @param x The data.
/// @param tolerance The convergence tolerance.
/// @default tolerance 1e-8
/// @export name=fit_model invisible
pub fn fit_model_zig(x: []const f64, tolerance: f64) f64 { ... }
```

generates `fit_model <- function(x, tolerance = 1e-8) invisible(...)`.
The options are `internal` (see below), `invisible` and `name=<R name>`;
any other option is an error of the scan.

## Exports in several files

`main.zig` can collect exports from other files of `src/rzig/src`:

``` zig
pub const stats = @import("stats.zig"); // exports in stats.zig are found
const helpers = @import("helpers.zig");

/// Three times a value.
/// @export
pub const triple = helpers.triple;       // re-exports helpers.triple as triple()
```

A function marked `/// @export` in a file that `main.zig` imports with
`pub const` (directly or through another such file) is registered under
its own name. A marker in a file imported with a plain `const` is an
error, because the generated registration can reach only public
declarations; a marked file that is not imported at all is ignored, and
[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
notes it. R names must be unique across all files.

## Internal routines

A native routine that only the package’s own R code calls is marked
`/// @export internal`. It is registered and gets an R wrapper, but the
wrapper is not exported from the package and gets no help page:

``` zig
/// Fit the penalized model for the R function fit_model().
/// @export internal
pub fn fit_model_zig(ctx: *rzig.Ctx, x: rzig.Matrix, y: []const f64) rzig.Error![]f64 {
    ...
}
```

``` r

fit_model <- function(x, y) {
  stopifnot(is.matrix(x), is.numeric(y))
  fit_model_zig(x, as.double(y))
}
```

## Faster builds on a development machine

Every installation compiles in a fresh copy of the package, and Zig
keeps its global cache inside that copy so that `R CMD check` and CRAN
find nothing written outside the package. With Zig 0.17 the first step
of each build then compiles Zig’s build runner again. On a development
machine, a persistent cache avoids that:

``` r

Sys.setenv(RZIG_ZIG_CACHE = tools::R_user_dir("rzig", "cache"))
```

Leave `RZIG_ZIG_CACHE` unset for checks of a package before release.

## Updating rzig in a package

After installing a new version of rzig, bring a package up to date with

``` r

rzig::update_rzig(pkg)
```

[`update_rzig()`](https://marekdejauj.github.io/rzig/reference/update_rzig.md)
replaces the framework sources under `src/rzig/framework`, updates every
build file that is still an unmodified rzig template, adds missing ones
and regenerates the bindings. It never changes `src/rzig/src` or files
rzig does not know, and it keeps build files the package author edited
(for example a `configure` that downloads Zig, or a `build.zig` with an
extra test step) and lists them, so their differences from the new
templates can be reviewed. `update_rzig(pkg, force = TRUE)` replaces
those as well.
[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
reports framework sources that do not match the installed rzig.

If roxygen2 generates `NAMESPACE` (its first line is
`# Generated by roxygen2: do not edit by hand`),
[`document()`](https://marekdejauj.github.io/rzig/reference/document.md)
writes the native-symbol directive into `R/rzig-wrappers.R` as a
`@rawNamespace` tag and adds the same lines roxygen2 writes to
`NAMESPACE`. The package then works whichever of
[`rzig::document()`](https://marekdejauj.github.io/rzig/reference/document.md),
[`roxygen2::roxygenise()`](https://roxygen2.r-lib.org/reference/roxygenize.html)
or `devtools::document()` ran last, and roxygen2 writes the help pages
of the exported Zig functions. Run
[`rzig::document()`](https://marekdejauj.github.io/rzig/reference/document.md)
after changing an exported Zig signature, so that the wrappers follow
it. When devtools and rzig are both attached, one
[`document()`](https://marekdejauj.github.io/rzig/reference/document.md)
masks the other; call
[`rzig::document()`](https://marekdejauj.github.io/rzig/reference/document.md)
explicitly. If `roxygenise()` loaded the package in the current R
session, restart R before calling newly installed native exports.

## What `document()` generates

Every public Zig function with a `/// @export` line produces:

- a compile-time Zig manifest entry;
- an R wrapper with the visible Zig parameter names;
- an explicitly resolved native symbol in `NAMESPACE`;
- a roxygen block derived from the Zig doc comment; and
- a help page `man/<name>.Rd` written from the same comment (the first
  paragraph gives the title and description; `@param`, `@return`,
  `@examples`, `@details`, `@seealso`, `@references` and `@note` fill
  their sections). In a package documented with roxygen2, roxygen2
  writes the page from the roxygen block instead.

The first `*rzig.Ctx` parameter is supplied by RZig and omitted from the
R function. The complete input surface is:

| Zig parameter | Accepted R value | Conversion |
|----|----|----|
| `f64` | length-one double, integer, or logical | checked scalar |
| `i32` | length-one double, integer, or logical | checked whole number |
| `bool` | length-one logical | checked scalar |
| `usize` | length-one double, integer, or logical | checked whole number from 0 to 2147483647 |
| `i64` | length-one `bit64::integer64`, double, or integer | checked whole number; doubles up to 2^53 - 1 in absolute value |
| `?f64`, `?i32`, `?bool`, `?usize`, `?i64` | corresponding scalar, `NA`, or `NULL` | missing values become `null` |
| `[]const f64` | double vector | borrowed, read-only |
| `[]const i32` | integer vector | borrowed, read-only |
| `[]const i64` | `bit64::integer64` vector | borrowed, read-only; `NA` is `rzig.NA.integer64` |
| `[]const bool` | logical vector without `NA` | copied into the call arena |
| `[]const rzig.Logical` | logical vector | borrowed, read-only; elements `.TRUE`, `.FALSE`, `.NA` |
| `[]const u8` | one non-`NA` character value | copied as UTF-8 |
| `[]const []const u8` | character vector without `NA` | copied as UTF-8 |
| `[]const ?[]const u8` | character vector | copied as UTF-8; `NA` becomes `null` |
| `?[]const u8` | one character value, `NA`, or `NULL` | copied as UTF-8; `NA` and `NULL` become `null` |
| `rzig.Complex` | length-one complex, double, or integer | checked scalar; `NA` errors |
| `[]const rzig.Complex` | complex vector | borrowed, read-only, layout of `Rcomplex` |
| `rzig.Raw` | raw vector | borrowed bytes in `.data` |
| `rzig.Record(T)` | named list | entries read into the fields of struct `T` by name; defaults fill missing entries |
| `rzig.DataFrame(T)` | data frame | columns read into the fields of struct `T`; `.nrow` rows |
| `rzig.Factor` | factor | `.codes` borrowed, `.levels` copied |
| `rzig.CscMatrix` | `Matrix::dgCMatrix` | slots `i`, `p`, `x` borrowed and checked; `column(j)` |
| [`?T`](https://rdrr.io/r/base/logical.html) | `T`, or `NULL` | `NULL` becomes `null` (scalars also map `NA` to `null`) |
| `rzig.Matrix` | double matrix | borrowed, read-only, column-major |
| `rzig.IntMatrix` | integer matrix | borrowed, read-only, column-major; `NA` is `std.math.minInt(i32)` |
| `rzig.BoolMatrix` | logical matrix without `NA` | copied into the call arena |
| `rzig.Mut([]f64)`, `rzig.Mut([]i32)` | double or integer vector | duplicated before writable access |
| `rzig.Mut(rzig.Matrix)`, `rzig.Mut(rzig.IntMatrix)` | double or integer matrix | duplicated with its attributes before writable access |
| `rzig.Sexp` | any R object | borrowed low-level handle |
| `rzig.Function` | function | borrowed; [`call()`](https://rdrr.io/r/base/call.html) evaluates it from Zig |

Supported return values are:

| Zig return | R result |
|----|----|
| `void` | `NULL` |
| `f64`, `i32`, `bool` | length-one double, integer, or logical |
| `i64`, `[]const i64` / `[]i64` | `bit64::integer64` value or vector |
| `[]const f64` / `[]f64` | double vector |
| `[]const i32` / `[]i32` | integer vector |
| `[]const bool` / `[]bool` | logical vector |
| `[]const rzig.Logical` / `[]rzig.Logical` | logical vector that can contain `NA` |
| `[]const u8` | length-one character vector |
| `[]const []const u8` / `[][]const u8` | character vector |
| `[]const ?[]const u8` / `[]?[]const u8` | character vector; `null` becomes `NA` |
| `rzig.Complex` | length-one complex vector |
| `[]const rzig.Complex` / `[]rzig.Complex` | complex vector |
| `rzig.Raw` | raw vector |
| `rzig.Record(T)` / `rzig.DataFrame(T)` | named list / data frame built from the fields of `T` |
| `rzig.Factor` | factor |
| `rzig.List` | named R list |
| `rzig.Attributed(T)` | supported vector `T` with names, dimensions, dimnames, or classes |
| `rzig.Sexp` | the supplied R object |
| `rzig.Function` | the supplied function |
| [`?T`](https://rdrr.io/r/base/logical.html) | supported `T`, or `NULL` when `null` |

Any supported return may be wrapped in `rzig.Error!T`. `usize` and the
matrix views are parameter-only. Unsupported signatures fail at compile
time with the function and parameter position in the error.

## Errors and warnings

`rzig.raise()` records a message and returns `rzig.Error`, so it can be
returned directly or propagated with `try`. `rzig.warn()` queues a
warning for delivery after Zig cleanup and returns `void`, so call it
without `try`:

``` zig
if (values.len == 0) rzig.warn("received an empty vector", .{});
```

## Returning named lists

`rzig.List` collects supported return values in Zig-owned memory and
converts them to one named R list only after the function returns:

``` zig
/// Return values together with their length.
/// @export
pub fn summarize(ctx: *rzig.Ctx, values: []const f64) rzig.Error!rzig.List {
    if (values.len > std.math.maxInt(i32)) return rzig.raise("too many values", .{});
    var result = rzig.List.init(ctx);
    try result.put("values", values);
    try result.put("count", @as(i32, @intCast(values.len)));
    return result;
}
```

List entries may contain `f64`, `i32`, `bool`, double, integer, or
logical slices, UTF-8 strings or string vectors, optional values, or
`rzig.Sexp`. Names are copied into the call context, and no R object is
allocated until boundary conversion begins.

## Lists, data frames and factors

`rzig.Record(T)` reads a named list into the struct `T`, field by field;
a field with a default value may be missing from the list, an optional
field becomes `null`, and an unknown entry gives a warning. One record
argument carries any number of values, beyond the 32 arguments of a
function:

``` zig
const Options = struct {
    tolerance: f64 = 1e-8,
    @"max.iter": i32 = 100,
    weights: ?[]const f64 = null,
};

/// @export
pub fn fit(x: []const f64, options: rzig.Record(Options)) f64 {
    _ = options.value.@"max.iter";
    return x[0] * options.value.tolerance;
}
```

`rzig.DataFrame(T)` reads the columns of a data frame (slices or
`rzig.Factor`) and its number of rows; other columns are ignored, and
every column must have one value per row. `rzig.Factor` holds the
1-based codes and the levels of a factor. All three are also return
types: a record becomes a named list, a data frame gets compact row
names, and a factor’s codes are checked against its levels.

## Classes

A struct marked `/// @class` becomes an R class: `init` is the
constructor, exported under the struct’s name, and every public function
that takes the struct as its first parameter is a method, called with
`$`:

``` zig
/// A running mean.
/// @class
pub const RunningMean = struct {
    total: f64 = 0,
    count: usize = 0,

    /// Create an empty running mean.
    pub fn init() RunningMean {
        return .{};
    }

    /// Add values.
    pub fn add(self: *RunningMean, values: []const f64) void {
        for (values) |value| self.total += value;
        self.count += values.len;
    }

    /// The mean of the values added so far.
    pub fn mean(self: *const RunningMean) f64 {
        return self.total / @as(f64, @floatFromInt(self.count));
    }
};
```

``` r

m <- RunningMean()
m$add(c(1, 2, 3))
m$mean()
#> [1] 2
```

[`document()`](https://marekdejauj.github.io/rzig/reference/document.md)
generates the constructor, a `$` method, a `print` method that lists the
methods, completion of method names, and a help page with a Methods
section; the object is an `rzig.External(RunningMean)`.

## Values that live across calls

`rzig.External(T)` keeps a Zig value between calls in an R object (an
external pointer with the classes `c("T", "rzig_external")`). A function
returns `rzig.External(T).create(ctx, value)`, and later calls receive
the value through `.ptr` and may modify it; when R garbage-collects the
object, `T.deinit()` runs (it must not call R) and the memory is
released:

``` zig
const Counter = struct {
    count: i32 = 0,
    pub fn deinit(self: *Counter) void {
        _ = self;
    }
};

/// @export
pub fn counter(ctx: *rzig.Ctx) rzig.Error!rzig.External(Counter) {
    return rzig.External(Counter).create(ctx, .{});
}

/// @export
pub fn increment(c: rzig.External(Counter)) i32 {
    c.ptr.count += 1;
    return c.ptr.count;
}
```

Memory that the value refers to must outlive the call: allocate it with
`std.heap.c_allocator` and free it in `deinit`, not with the call
context. An object of another type or package is rejected by its tag. A
value saved with [`saveRDS()`](https://rdrr.io/r/base/readRDS.html) or
in a workspace is lost, and using it is an error that asks to create it
again.

## Reading R objects

An `rzig.Sexp` parameter borrows any R object. Its read-only methods
report `kind()` (`.double`, `.list`, `.s4`, …),
[`length()`](https://rdrr.io/r/base/length.html), `isNull()`,
`isObject()`, [`isS4()`](https://rdrr.io/r/base/isS4.html) and
`inherits(class)`, read `attribute(name)` (S4 slots are attributes),
`names(ctx)` and `classes(ctx)`, walk a list with `element(index)` and
`field(name)`, and convert a value with `get(T, ctx)` by the rules of a
parameter of type `T`:

``` zig
/// @export
pub fn total(ctx: *rzig.Ctx, value: rzig.Sexp) rzig.Error!f64 {
    const entry = (try value.field("x")) orelse return rzig.raise("no entry x", .{});
    var sum: f64 = 0;
    for (try entry.get([]const f64, ctx)) |x| sum += x;
    return sum;
}
```

## Mutable inputs

Mutation is opt-in with `rzig.Mut([]f64)`, `rzig.Mut([]i32)`,
`rzig.Mut(rzig.Matrix)` or `rzig.Mut(rzig.IntMatrix)`. RZig duplicates
and protects the R vector or matrix before Zig receives writable
storage, then returns that duplicate, which keeps the attributes of the
input (`dim`, `dimnames`, `class`):

``` zig
/// Scale a copy of a numeric vector.
/// @export
pub fn scale(values: rzig.Mut([]f64), factor: f64) void {
    for (values.data) |*value| value.* *= factor;
}
```

The caller’s vector and any aliases remain unchanged. A function using
`Mut` accepts one mutable vector and returns `void` or
`rzig.Error!void`; its generated R wrapper returns the mutated duplicate
automatically.

## Attributes and matrices

`rzig.Matrix` borrows an R double matrix in column-major order and
provides its validated shape through `nrow` and `ncol`; `rzig.IntMatrix`
borrows an integer matrix, and `rzig.BoolMatrix` copies a logical matrix
without `NA`. `at(row, column)` reads one element and `column(j)`
returns one column as a slice (zero-based indices). A matrix of another
storage mode is rejected with the
[`storage.mode()`](https://rdrr.io/r/base/mode.html) call that converts
it in R. `rzig.Mut(rzig.Matrix)` exposes `set(row, column, value)` as
well:

``` zig
/// Center each column of a numeric matrix.
/// @export
pub fn center_columns(values: rzig.Mut(rzig.Matrix)) void {
    for (0..values.data.ncol) |j| {
        const column = values.data.column(j);
        var mean: f64 = 0;
        for (column) |value| mean += value;
        mean /= @floatFromInt(column.len);
        for (column) |*value| value.* -= mean;
    }
}
```

Use `rzig.Attributed([]const f64)` to return a numeric vector with
metadata:

``` zig
pub fn labeled(
    ctx: *rzig.Ctx,
    values: []const f64,
    labels: []const []const u8,
) rzig.Error!rzig.Attributed([]const f64) {
    var result = rzig.Attributed([]const f64).init(ctx, values);
    try result.setNames(labels);
    try result.setClass("labeled_values");
    return result;
}
```

`setNames`, `setDim`, `setClass`, and `setClasses` copy their metadata
into the call context; `setMatrix(nrow, ncol)` sets a two-dimensional
`dim` and `setDimnames(row_names, column_names)` names the rows and
columns (`null` leaves a dimension unnamed). Lengths and dimension
products are checked before R allocation.

## Long-running loops

Call `try rzig.checkInterrupt()` about every 100,000 iterations of a
long loop. It probes through an R trampoline that catches the runtime’s
non-local interrupt exit, allowing Zig cleanup to finish before the
boundary returns an R error.

## Distributions

`rzig.Rmath.density`, `rzig.Rmath.cdf` and `rzig.Rmath.quantile`
evaluate the distributions of R (`.normal`, `.uniform`, `.gamma`,
`.beta`, `.binomial`, `.poisson`, `.exponential`, `.t`, `.chisq`, `.f`,
`.lognormal`, `.weibull`, `.logistic`, `.cauchy`, `.geometric`,
`.hypergeometric`, `.negative_binomial`), with R’s parameter names and
defaults, and `rng.draw(distribution, params)` draws from R’s generator,
so the draws follow [`set.seed()`](https://rdrr.io/r/base/Random.html):

``` zig
const p = try rzig.Rmath.cdf(.gamma, x, .{ .shape = 2 }, .{ .lower_tail = false });
const d = try rzig.Rmath.density(.normal, x, .{ .mean = 1 }, .{ .log = true });
const rng = try ctx.rng();
const draw = rng.draw(.poisson, .{ .lambda = 3 });
```

## Reductions, random streams and interrupts in parallel loops

`rzig.parallelReduce(ctx, T, count, &state, identity, map, combine)`
reduces `map(state, i)` with `combine` in chunks fixed by `count`, so a
parallel floating-point sum is the same for every number of threads.
`ctx.rngStreams()` gives workers random streams seeded from R’s stream:
`streams.stream(i)` is the same for the same seed and index, so parallel
draws follow [`set.seed()`](https://rdrr.io/r/base/Random.html). A user
interrupt stops the workers after their current index, and a panic on a
worker (for example a failed bounds check) becomes an R error instead of
ending the session.

## Linear algebra

`rzig.Blas` (`gemm`, `gemv`, `syrk`, `trsm`) and `rzig.Lapack` (`potrf`,
`potrs`, `getrf`, `getrs`, `gesv`, `geqrf`, `ormqr`, `gels`, `syevr`,
`gesdd`) call the BLAS and LAPACK that R uses, on column-major matrices:
`rzig.Matrix` operands and `rzig.MutableMatrix` results, for example
from `ctx.matrix(nrow, ncol)` or `rzig.Mut(rzig.Matrix)`. Every routine
checks the shapes before the call and turns LAPACK’s `info` into an R
error, such as “the matrix is not positive definite”. A package that
uses them runs `use_rzig_lapack(path)` once, so that it links
`$(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)`:

``` zig
/// @export
pub fn crossprod(ctx: *rzig.Ctx, x: rzig.Matrix) rzig.Error!rzig.Attributed([]f64) {
    const out = try ctx.matrix(x.ncol, x.ncol);
    try rzig.Blas.gemm(ctx, .yes, .no, 1, x, x, 0, out);
    var result = rzig.Attributed([]f64).init(ctx, out.data);
    try result.setMatrix(out.nrow, out.ncol);
    return result;
}
```

## Calling R functions from Zig

An `rzig.Function` parameter receives an R function, and
`f.call(ctx, T, args)` calls it on the thread that entered R. `args` is
a tuple of positional arguments or a struct of named ones, with values
of any type an exported function can return; the result is converted to
`T` like an argument (`void` ignores it).

``` zig
pub fn apply_twice(ctx: *rzig.Ctx, f: rzig.Function, x: []const f64) rzig.Error![]const f64 {
    const once = try f.call(ctx, []const f64, .{x});
    return f.call(ctx, []const f64, .{ .x = once });
}
```

An R error, an interrupt, or a condition handler or restart outside the
call that takes control returns `rzig.Error`. Return it, and R continues
the error with its class and call once the Zig frames have run their
`defer` blocks, so
[`tryCatch()`](https://rdrr.io/r/base/conditions.html),
[`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html) and
[`traceback()`](https://rdrr.io/r/base/traceback.html) behave as they
would without Zig in between. The calls appear as `f(...)`, with the
name of the R argument. A borrowed result stays allocated until the
exported function returns, and R’s random-number state passes to R and
back when `ctx.rng()` is in use. Objectives and integrands of
`rzig.Optimize` and `rzig.Integrate` may call R functions.

## Optimization and integration

`rzig.Optimize.minimize(ctx, method, &problem, x, options)` runs the
optimizers of [`optim()`](https://rdrr.io/r/stats/optim.html) (`.bfgs`,
`.nelder_mead`, `.conjugate_gradient`, `.lbfgsb` with bounds) on a Zig
objective: `problem` has `value(x)` and, optionally, `gradient(x, g)`;
without one, central differences use the step of
[`optim()`](https://rdrr.io/r/stats/optim.html).
`rzig.Integrate.integrate(ctx, &f, lower, upper, .{})` integrates
`f.value(x)` as [`integrate()`](https://rdrr.io/r/stats/integrate.html)
does, with infinite limits allowed. Errors of the callbacks are reported
when the routine finishes.

``` zig
const Problem = struct {
    data: []const f64,
    pub fn value(self: *const Problem, x: []const f64) f64 {
        var total: f64 = 0;
        for (self.data) |y| total += (y - x[0]) * (y - x[0]);
        return total;
    }
};

const x = try ctx.dupe(f64, &.{0.0});
const result = try rzig.Optimize.minimize(ctx, .bfgs, &Problem{ .data = data }, x, .{});
```

## Pure Zig parallel loops

`rzig.parallelFor` distributes an indexed computation across Zig worker
threads. Its state is checked at compile time: `Ctx`, `Sexp`, matrices,
list builders, mutable inputs, attributed results, opaque pointers, and
function pointers cannot cross into a worker.

``` zig
const Work = struct {
    input: []const f64,
    output: []f64,

    fn square(work: *@This(), index: usize) void {
        work.output[index] = work.input[index] * work.input[index];
    }
};

pub fn squares(ctx: *rzig.Ctx, input: []const f64) rzig.Error![]f64 {
    const output = try ctx.alloc(f64, input.len);
    var work = Work{ .input = input, .output = output };
    try rzig.parallelFor(ctx, input.len, &work, Work.square);
    return output;
}
```

The callback has the exact signature `fn(*State, usize) void` and always
runs off the R thread. It must be panic-free and must not import or call
R or RZig APIs. If a worker can fail, record that in atomic plain-data
state, wait for `parallelFor` to join every worker, and call
`rzig.raise` on the calling thread.

`parallelFor` starts one worker thread per core, at most 32 and at most
one per index. The environment variable `RZIG_NUM_THREADS` lowers that
number (for example `Sys.setenv(RZIG_NUM_THREADS = 2)` in R),
`OMP_THREAD_LIMIT` is respected as well, and while `R CMD check` limits
the cores (`_R_CHECK_LIMIT_CORES_`, set for CRAN submissions) at most
two threads run, as the CRAN policy requires.
`rzig.parallelThreadCount(count)` returns the number of threads a call
would use, for example to size per-thread buffers.

## Safety model

RZig keeps R’s non-local error mechanism at the outer native boundary.
Internal Zig code returns explicit errors, all Zig-owned cleanup
finishes before an R error is raised, and cleanup is protected if an R
API call jumps out. A jump of R out of R code that Zig calls
(`rzig.Function`) stops before the Zig frames and resumes after them.
Inputs are borrowed read-only, return slices are copied into R-owned
memory, and generated packages build in `ReleaseSafe` mode so bounds and
overflow checks stay enabled.

R’s API remains single-threaded. Zig code may parallelize pure
computation, but must not call R from worker threads.

## Development checks

The package tests run with `R CMD check` and need no Zig. The repository
test suite runs with Zig 0.16.0 and 0.17.0:

``` sh
zig build test
zig build --release=safe
zig build lint
R CMD build tests/fixtures/rzigtest
```

Continuous integration builds and checks the fixture package on Linux,
macOS, and Windows, and runs GC-stress and memory-analysis profiles
where available.

## Stability

From version 1.0.0, rzig follows semantic versioning for its public
interface: the exported R functions, the declarations of the Zig module
`rzig` except `rzig.internal`, the markers and options of the Zig source
(`/// @export`, `/// @class`, `@default`), the fields of `DESCRIPTION`
that it reads (`Config/rzig/...`), and the files it writes into a
package. A change that breaks code using them comes with a new major
version; additions come with minor versions. `rzig.internal`, the
generated manifest and the framework files under `src/rzig/framework`
are rzig’s own and change with any version;
[`update_rzig()`](https://marekdejauj.github.io/rzig/reference/update_rzig.md)
replaces them.

Zig changes between release series, so rzig supports the two most recent
series it has been tested with (0.16 and 0.17 for rzig 1.0.0). Support
for a new series comes with a minor version; a series is dropped in a
minor version that NEWS announces one version ahead.

## Packages using rzig

- [pnsbib](https://github.com/MarekDejaUJ/pnsbib): probabilities of
  causation with partial information, bounded from observational and
  interventional distributions.

The vignettes and `inst/examples/poclp` (the case study of the article
on rzig) show further packages.

## License

GPL-3. See
[COPYING](https://github.com/MarekDejaUJ/rzig/blob/main/COPYING) for the
full license text. RZig 0.2.3 and earlier releases on CRAN were
published under the MIT license.
