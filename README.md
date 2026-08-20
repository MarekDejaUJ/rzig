# RZig

RZig lets R package authors write plain Zig functions and generate safe `.Call`
bindings without C++ or hand-written `SEXP` conversion code.

RZig is experimental. Its API may change before version 0.1.0.

## Requirements

- R and the platform toolchain used to build R source packages
- Zig 0.16.0 available as `zig`, or through the `ZIG` environment variable

Confirm the Zig version before starting:

```sh
zig version
# 0.16.0
```

On Windows, install the Rtools version appropriate for your R installation. On
macOS, install the Xcode command-line tools. Linux needs a C compiler and the R
development headers.

## Install RZig

Until the first CRAN release, install from GitHub:

```r
install.packages("remotes")
remotes::install_github("MarekDejaUJ/rzig")
```

If Zig is not on `PATH`, tell RZig where it is:

```r
Sys.setenv(ZIG = "/absolute/path/to/zig")
```

## Create a working package

Start in R from the directory where the package should be created:

```r
pkg <- "rzhello"
dir.create(pkg)
writeLines(
  c(
    "Package: rzhello",
    "Type: Package",
    "Title: A Small RZig Example",
    "Version: 0.0.1",
    "Authors@R: person('Your', 'Name', email = 'you@example.org', role = c('aut', 'cre'))",
    "Description: Demonstrates a Zig implementation called safely from R.",
    "License: MIT",
    "Encoding: UTF-8"
  ),
  file.path(pkg, "DESCRIPTION")
)
rzig::use_rzig(pkg)
```

Replace `rzhello/src/rzig/src/main.zig` with:

```zig
const std = @import("std");
const builtin = @import("builtin");
const rzig = @import("rzig");

pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    rzig.Panic;

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

comptime {
    rzig.registerModule(@This());
}
```

Generate the bindings and install the package:

```r
rzig::document(pkg)
status <- system2(
  file.path(R.home("bin"), "R"),
  c("CMD", "INSTALL", shQuote(normalizePath(pkg)))
)
stopifnot(status == 0L)
```

The generated R function is ready to call:

```r
library(rzhello)

add_vectors(c(1, 2, 3), c(10, 20, 30))
#> [1] 11 22 33

add_vectors(c(1, 2), c(1, 2, 3))
#> Error: lengths differ: 2 vs 3

# The session remains usable after the native error.
add_vectors(c(4, 5), c(6, 7))
#> [1] 10 12
```

The same workflow applies to an existing package: run `use_rzig()` once, edit
`src/rzig/src/main.zig`, and run `document()` whenever exported Zig signatures
or comments change.

## What `document()` generates

Every public Zig function with a `/// @export` line produces:

- a compile-time Zig manifest entry;
- an R wrapper with the visible Zig parameter names;
- an explicitly resolved native symbol in `NAMESPACE`; and
- a roxygen block derived from the Zig doc comment.

The first `*rzig.Ctx` parameter is supplied by RZig and is omitted from the R
function. Other parameters are converted according to their Zig types. Current
scalar inputs include `f64`, `i32`, `bool`, `usize`, and optional forms. Current
borrowed inputs include numeric, integer, logical, string, and string-vector
slices. Unsupported signatures fail at compile time with the function and
parameter position in the error.

## Safety model

RZig keeps R's non-local error mechanism at the outer native boundary. Internal
Zig code returns explicit errors, all Zig-owned cleanup finishes before an R
error is raised, and cleanup is protected if an R API call jumps out. Inputs are
borrowed read-only, return slices are copied into R-owned memory, and generated
packages build in `ReleaseSafe` mode so bounds and overflow checks stay enabled.

R's API remains single-threaded. Zig code may parallelize pure computation, but
must not call R from worker threads.

## Development checks

The repository test suite uses Zig 0.16.0:

```sh
zig build test
zig build --release=safe
zig build lint
R CMD build tests/fixtures/rzigtest
```

Continuous integration builds and checks the fixture package on Linux, macOS,
and Windows, and runs GC-stress and memory-analysis profiles where available.

## License

MIT
