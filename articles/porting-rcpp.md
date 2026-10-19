# Porting a C++ hot loop from Rcpp to RZig

RZig is most useful when an R package has a small, computationally
expensive loop that needs native performance but does not otherwise need
C++. This vignette ports an `axpy`-style operation: return
`x + scale * y` without modifying either R input. Every step up to the
installation runs in R without a Zig compiler; the installation and the
calls run when a supported compiler is found.

## Start from the behavior, not the wrapper

An Rcpp implementation might duplicate `x`, validate the inputs, and
mutate the duplicate in place:

``` cpp
#include <Rcpp.h>

// [[Rcpp::export]]
Rcpp::NumericVector axpy_rcpp(
    Rcpp::NumericVector x,
    const Rcpp::NumericVector& y,
    double scale
) {
    if (x.size() != y.size()) Rcpp::stop("x and y must have equal lengths");

    Rcpp::NumericVector result = Rcpp::clone(x);
    for (R_xlen_t i = 0; i < result.size(); ++i) {
        if (i % 100000 == 0) Rcpp::checkUserInterrupt();
        result[i] += scale * y[i];
    }
    return result;
}
```

The important contract is not the C++ class structure. It is that `y` is
read only, `x` is duplicated before mutation, unequal lengths become an
R error, and long computations remain interruptible.

## Scaffold the Zig-backed package

Set the package path explicitly, then run
[`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md)
once. This disposable example stays inside R’s session temporary
directory; for a real project, replace `package_path` with its explicit
package root:

``` r

package_path <- tempfile("yourpackage-", tmpdir = tempdir())
dir.create(package_path)
writeLines(
  c(
    "Package: yourpackage",
    "Type: Package",
    "Title: A Small RZig Example",
    "Version: 0.0.1",
    "Authors@R: person('Your', 'Name', email = 'you@example.org', role = c('aut', 'cre'))",
    "Description: Demonstrates a native implementation written in Zig.",
    "License: GPL-3",
    "Encoding: UTF-8"
  ),
  file.path(package_path, "DESCRIPTION")
)
scaffold <- use_rzig(package_path)
#> Generated RZig bindings for yourpackage: 1 exported function
#> Created RZig scaffold for package yourpackage
scaffold
#> RZig scaffold of package yourpackage: 52 files written
#> Zig source: src/rzig/src/main.zig
#> Exported functions: hello_zig
#> Next steps: edit main.zig, run document(), then install the package with a Zig compiler (see find_zig()).
```

[`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md)
creates the portable build files, the Zig source tree with the
framework, a starter `src/rzig/src/main.zig`, and the generated R
wrapper for the starter function. The Zig implementation of the port is
shipped with RZig as `inst/examples/axpy.zig`; copying it over the
starter file is the only edit the port needs:

``` r
main_path <- file.path(package_path, "src", "rzig", "src", "main.zig")
file.copy(system.file("examples", "axpy.zig", package = "rzig"), main_path,
  overwrite = TRUE)
[1] TRUE
cat(readLines(main_path), sep = "\n")
const std = @import("std");
const builtin = @import("builtin");
const rzig = @import("rzig");

pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    rzig.Panic;

/// Compute x + scale * y without changing either R input.
/// @param x The numeric vector to duplicate and update.
/// @param y A borrowed, read-only numeric vector.
/// @param scale The multiplier applied to y.
/// @return A new numeric vector containing the result.
/// @export
pub fn axpy(
    x: rzig.Mut([]f64),
    y: []const f64,
    scale: f64,
) rzig.Error!void {
    if (x.data.len != y.len) {
        return rzig.raise(
            "x and y must have equal lengths; got {d} and {d}",
            .{ x.data.len, y.len },
        );
    }

    for (x.data, y, 0..) |*result, value, index| {
        if (index % 100_000 == 0) try rzig.checkInterrupt();
        result.* += scale * value;
    }
}

comptime {
    rzig.registerModule(@This());
}
```

`rzig.Mut([]f64)` is the direct expression of copy-on-modify semantics.
RZig duplicates and protects `x` before Zig receives writable storage.
The `y` slice borrows R’s numeric storage as read-only memory. Because
this function returns `void`, the generated boundary returns the mutated
duplicate automatically.

The function contains no `SEXP`, `PROTECT`, C++ exception, or
registration table. The types and `@export` marker supply enough
information for RZig to generate those parts.

## Inspect what R will see

[`scan_exports()`](https://marekdejauj.github.io/rzig/reference/scan_exports.md)
reads the Zig source and lists every exported function with its R
arguments and the R value of each parameter and of the result:

``` r

scan_exports(package_path)
#> Zig exports of package yourpackage (src/rzig/src/main.zig): 1 function
#> 
#> axpy(x, y, scale)
#>   x          rzig.Mut([]f64)        double vector, writable duplicate
#>   y          []const f64            double vector, borrowed
#>   scale      f64                    double, length 1
#>   returns    rzig.Error!void        the writable duplicate, a double vector
```

## Generate the bindings

[`document()`](https://marekdejauj.github.io/rzig/reference/document.md)
writes the Zig manifest, the R wrapper and the `NAMESPACE` block. Run it
whenever an exported Zig signature or its documentation changes. The
returned object holds the generated texts:

``` r

bindings <- document(package_path)
#> Generated RZig bindings for yourpackage: 1 exported function
cat(bindings$wrappers)
#> # Generated by rzig::document(). Do not edit.
#> 
#> #' Compute x + scale * y without changing either R input.
#> #' @param x The numeric vector to duplicate and update.
#> #' @param y A borrowed, read-only numeric vector.
#> #' @param scale The multiplier applied to y.
#> #' @return A new numeric vector containing the result.
#> #'
#> #' @export
#> axpy <- function(x, y, scale) {
#>   .Call(axpy_, x, y, scale)
#> }
cat(bindings$namespace)
#> # Generated by rzig::document(): begin
#> useDynLib("yourpackage",
#>   axpy_ = "axpy"
#> )
#> export("axpy")
#> # Generated by rzig::document(): end
```

[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
checks every step and tells whether the generated bindings match the
current Zig source and whether a supported Zig compiler is available for
the installation:

``` r

rzig_status(package_path)
#> RZig status of package yourpackage
#>   [ok] DESCRIPTION   package yourpackage
#>                      SystemRequirements does not name Zig; state the
#>                        supported series, for example "Zig 0.16.x or 0.17.x"
#>   [ok] Scaffold      build files and framework sources present
#>   [ok] Zig source    src/rzig/src/main.zig
#>   [ok] Exports       1 function: axpy
#>   [ok] Bindings      generated files match the exports
#>   [ok] Zig compiler  /home/runner/work/_temp/0beafb3f-08c9-475d-9a85-dbeb3ad24ddb/zig-x86_64-linux-0.16.0/zig
#>                        (version 0.16.0)
#>   [ok] C toolchain   C compiler gcc
```

## Check the signature before compiling

[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
also rejects, before any compilation, the signatures the boundary cannot
convert. A single-precision argument is one such case:

``` r

broken_path <- tempfile("brokenpackage-", tmpdir = tempdir())
dir.create(broken_path)
writeLines(c("Package: brokenpackage", "Version: 0.0.1"),
  file.path(broken_path, "DESCRIPTION"))
invisible(use_rzig(broken_path))
#> Generated RZig bindings for brokenpackage: 1 exported function
#> Created RZig scaffold for package brokenpackage
broken_main <- file.path(broken_path, "src", "rzig", "src", "main.zig")
cat("/// @export\npub fn half(x: f32) f32 {\n    return x / 2;\n}\n",
  file = broken_main, append = TRUE)
rzig_status(broken_path)
#> RZig status of package brokenpackage
#>   [ok] DESCRIPTION   package brokenpackage
#>                      R CMD check also requires Title, Description, License,
#>                        Authors@R
#>                      SystemRequirements does not name Zig; state the
#>                        supported series, for example "Zig 0.16.x or 0.17.x"
#>   [ok] Scaffold      build files and framework sources present
#>   [ok] Zig source    src/rzig/src/main.zig
#>   [--] Exports       `half`, argument `x`: type f32 is not supported; use f64
#>                      `half`: return type f32 is not supported
#>   [--] Bindings      out of date: manifest.zig, R/rzig-wrappers.R, NAMESPACE,
#>                        man/half.Rd; run document()
#>   [ok] Zig compiler  /home/runner/work/_temp/0beafb3f-08c9-475d-9a85-dbeb3ad24ddb/zig-x86_64-linux-0.16.0/zig
#>                        (version 0.16.0)
#>   [ok] C toolchain   C compiler gcc
#> 2 of 7 checks failed: Exports, Bindings
```

## Build and call

[`build_zig()`](https://marekdejauj.github.io/rzig/reference/build_zig.md)
compiles and installs the package from a copy in the session temporary
directory. It runs the checks of
[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
first, keeps the complete installation log, and on failure reports the
first errors of the Zig compiler, the C compiler, the linker or the load
test with their files and lines. The build needs a Zig compiler of a
supported release series. The chunks below run when
[`find_zig()`](https://marekdejauj.github.io/rzig/reference/find_zig.md)
finds one; this rendered copy of the vignette ran them.

``` r

build <- build_zig(package_path)
build
#> Build of package yourpackage: succeeded in 9.2 seconds
#> Zig compiler: /home/runner/work/_temp/0beafb3f-08c9-475d-9a85-dbeb3ad24ddb/zig-x86_64-linux-0.16.0/zig (version 0.16.0)
#> Installed into a library in the session temporary directory
package_name <- "yourpackage"
loadNamespace(package_name, lib.loc = build$library)
#> <environment: namespace:yourpackage>
axpy <- getExportedValue(package_name, "axpy")
```

The generated R function has the same three visible arguments:

``` r

x <- c(1, 2, 3)
y <- c(10, 20, 30)
result <- axpy(x, y, 0.5)
x
#> [1] 1 2 3
result
#> [1]  6 12 18
try(axpy(1:2, c(1, 2, 3), 1))
#> Error : rzig: argument `x` of axpy must be a numeric vector for rzig.Mut([]f64); got integer; use as.numeric() in R
sum(1:10)
#> [1] 55
```

The native error is an R condition, and the session remains usable.
Integer vectors are rejected for numeric slices and mutable numeric
inputs. Convert deliberately with
[`as.numeric()`](https://rdrr.io/r/base/numeric.html) in R rather than
relying on an implicit native allocation.

## What changes in the port

Rcpp’s `NumericVector` combines an R object, indexing, allocation, and
mutation in one C++ class. RZig separates those capabilities. A borrowed
`[]const f64` cannot mutate its input. `rzig.Mut([]f64)` duplicates
before exposing writable storage. `rzig.Ctx` is used only when Zig-owned
scratch or result memory is needed. Errors are explicit `rzig.Error`
values, and the outer boundary turns them into R conditions after Zig
cleanup has finished.

Generated packages compile in Zig’s `ReleaseSafe` mode. Bounds checks
and integer-overflow checks therefore remain enabled in installed code.
A failure is routed through RZig’s panic boundary instead of silently
corrupting adjacent R memory.

## Measure the boundary separately

Benchmark the algorithm and the language boundary as separate questions.
For a hot loop, compare equivalent copy and mutation semantics, use the
same compiler optimization level, warm each implementation, randomize
execution order, and report distributions rather than one elapsed time.

The RZig repository includes `tests/bench.R`, which checks and times
equivalent RZig, handwritten C, and Rcpp round-trip copies at lengths 1,
1,000, and 1,000,000. It records medians and interquartile ranges from
randomized batches. This isolates conversion overhead from the workload
being ported.

## Port incrementally

Move one native function at a time and keep the surrounding R interface
stable. Tests should cover empty and large inputs, missing values, wrong
R types, length mismatches, and continued session use after each error.
C libraries can coexist with Zig during a gradual conversion. C++
classes and templates usually need to be redesigned as Zig structs and
explicit data flow rather than translated line by line.
