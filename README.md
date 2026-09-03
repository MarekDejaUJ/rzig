# RZig

RZig lets R package authors write plain Zig functions and generate safe `.Call`
bindings without C++ or hand-written `SEXP` conversion code.

RZig is an early 0.x release. Its API may change before version 1.0.0.

## Requirements

- R and the platform toolchain used to build R source packages
- Zig 0.16.0 or newer. Release verification uses Zig 0.16.0; newer versions are
  accepted but are not claimed as tested until they appear in the CI matrix.

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

Both `use_rzig()`/`document()` and the generated package configuration search
in this order: `ZIG`, `PATH`, `~/.local/share/zig/*/zig`, then `~/zig/zig`.
An R session launched from an IDE may not inherit variables exported by a shell;
in that case, set `ZIG` with `Sys.setenv()` before running either command.

## Create a working package

For a copy-paste-safe example, create the package in R's session temporary
directory. Replace `tempdir()` with an explicit project directory when keeping
the result:

```r
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
    "License: MIT",
    "Encoding: UTF-8"
  ),
  file.path(pkg, "DESCRIPTION")
)
rzig::use_rzig(pkg)
```

`use_rzig()` has already created `src/rzig/src/main.zig` below `pkg` with a
working `hello_zig()` example and all required framework wiring. Open that
file, keep its imports, `panic` declaration, and `comptime` registration block,
and replace only the generated `hello_zig()` function with:

```zig
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
`document()` generates neutral placeholders from the Zig signature. Only
`/// @export` is required to expose a public function to R.

Generate the bindings and install the package:

```r
rzig::document(pkg)
library_dir <- file.path(tempdir(), "rzhello-library")
dir.create(library_dir)
status <- system2(
  file.path(R.home("bin"), "R"),
  c(
    "CMD", "INSTALL",
    paste0("--library=", shQuote(library_dir)),
    shQuote(normalizePath(pkg))
  )
)
stopifnot(status == 0L)
```

The generated R function is ready to call:

```r
library(rzhello, lib.loc = library_dir)

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
or comments change. The scaffolded `cleanup` and `cleanup.win` scripts remove
generated Makevars and Zig build caches after package installation and checks.

If roxygen2 manages the rest of the package documentation and `NAMESPACE`, use
this order after changing a Zig export:

```r
rzig::document(pkg)       # generate wrappers for roxygen2 to read
roxygen2::roxygenise(pkg) # regenerate Rd files and the ordinary NAMESPACE
rzig::document(pkg)       # restore RZig's explicit native-registration block
```

The final call preserves non-RZig directives while replacing generated Zig
exports, so both tools retain ownership of their respective blocks. If
`roxygenise()` loaded the package in the current R session, unload it or restart
R before calling newly installed native exports.

## What `document()` generates

Every public Zig function with a `/// @export` line produces:

- a compile-time Zig manifest entry;
- an R wrapper with the visible Zig parameter names;
- an explicitly resolved native symbol in `NAMESPACE`; and
- a roxygen block derived from the Zig doc comment.

The first `*rzig.Ctx` parameter is supplied by RZig and omitted from the R
function. The complete input surface is:

| Zig parameter | Accepted R value | Conversion |
| --- | --- | --- |
| `f64` | length-one double, integer, or logical | checked scalar |
| `i32` | length-one double, integer, or logical | checked whole number |
| `bool` | length-one logical | checked scalar |
| `usize` | length-one double, integer, or logical | checked whole number from 0 to 2147483647 |
| `?f64`, `?i32`, `?bool`, `?usize` | corresponding scalar, `NA`, or `NULL` | missing values become `null` |
| `[]const f64` | double vector | borrowed, read-only |
| `[]const i32` | integer vector | borrowed, read-only |
| `[]const bool` | logical vector without `NA` | copied into the call arena |
| `[]const u8` | one non-`NA` character value | copied as UTF-8 |
| `[]const []const u8` | character vector without `NA` | copied as UTF-8 |
| `rzig.Matrix` | double matrix | borrowed, read-only, column-major |
| `rzig.Mut([]f64)` | double vector | duplicated before writable access |
| `rzig.Sexp` | any R object | borrowed low-level handle |

Supported return values are:

| Zig return | R result |
| --- | --- |
| `void` | `NULL` |
| `f64`, `i32`, `bool` | length-one double, integer, or logical |
| `[]const f64` / `[]f64` | double vector |
| `[]const i32` / `[]i32` | integer vector |
| `[]const bool` / `[]bool` | logical vector |
| `[]const u8` | length-one character vector |
| `[]const []const u8` / `[][]const u8` | character vector |
| `rzig.List` | named R list |
| `rzig.Attributed(T)` | supported vector `T` with names, dimensions, or classes |
| `rzig.Sexp` | the supplied R object |
| `?T` | supported `T`, or `NULL` when `null` |

Any supported return may be wrapped in `rzig.Error!T`. `usize` and
`rzig.Matrix` are parameter-only. Unsupported signatures fail at compile time
with the function and parameter position in the error.

## Errors and warnings

`rzig.raise()` records a message and returns `rzig.Error`, so it can be returned
directly or propagated with `try`. `rzig.warn()` queues a warning for delivery
after Zig cleanup and returns `void`, so call it without `try`:

```zig
if (values.len == 0) rzig.warn("received an empty vector", .{});
```

## Returning named lists

`rzig.List` collects supported return values in Zig-owned memory and converts
them to one named R list only after the function returns:

```zig
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

List entries may contain `f64`, `i32`, `bool`, double, integer, or logical
slices, UTF-8 strings or string vectors, optional values, or `rzig.Sexp`. Names
are copied into the call context, and no R object is allocated until boundary
conversion begins.

## Mutable numeric inputs

Mutation is opt-in with `rzig.Mut([]f64)`. RZig duplicates and protects the R
vector before Zig receives writable storage, then returns that duplicate:

```zig
/// Scale a copy of a numeric vector.
/// @export
pub fn scale(values: rzig.Mut([]f64), factor: f64) void {
    for (values.data) |*value| value.* *= factor;
}
```

The caller's vector and any aliases remain unchanged. A function using `Mut`
accepts one mutable vector and returns `void` or `rzig.Error!void`; its generated
R wrapper returns the mutated duplicate automatically.

## Attributes and matrices

`rzig.Matrix` borrows an R double matrix in column-major order and provides its
validated shape through `nrow` and `ncol`. Integer matrices are rejected rather
than silently copied; convert them in R with `storage.mode(x) <- "double"`.

Use `rzig.Attributed([]const f64)` to return a numeric vector with metadata:

```zig
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

`setNames`, `setDim`, `setClass`, and `setClasses` copy their metadata into the
call context. Lengths and dimension products are checked before R allocation.

## Long-running loops

Call `try rzig.checkInterrupt()` about every 100,000 iterations of a long loop.
It probes through an R trampoline that catches the runtime's non-local interrupt
exit, allowing Zig cleanup to finish before the boundary returns an R error.

## Pure Zig parallel loops

`rzig.parallelFor` distributes an indexed computation across Zig worker threads.
Its state is checked at compile time: `Ctx`, `Sexp`, matrices, list builders,
mutable inputs, attributed results, opaque pointers, and function pointers cannot
cross into a worker.

```zig
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

The callback has the exact signature `fn(*State, usize) void` and always runs
off the R thread. It must be panic-free and must not import or call R or RZig
APIs. If a worker can fail, record that in atomic plain-data state, wait for
`parallelFor` to join every worker, and call `rzig.raise` on the calling thread.

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
