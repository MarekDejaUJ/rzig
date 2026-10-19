# C sources, C libraries and code shared between packages

A package that uses RZig can keep C, C++ or Fortran sources next to its
Zig code, compile a C library that it ships, share a Zig module with
other packages, and offer C-callable functions to other packages. This
vignette shows the four forms. The scaffolds and checks are plain R; the
builds run when a supported Zig compiler is found (this copy ran them).

``` r

root <- file.path(tempdir(), "sharing")
dir.create(root)
lib <- file.path(root, "lib")
dir.create(lib)
header <- c(
  "const rzig = @import(\"rzig\");",
  "",
  "pub const panic = rzig.Panic;",
  "",
  "comptime {",
  "    rzig.registerModule(@This());",
  "}",
  ""
)
```

## C, C++ and Fortran sources next to Zig

[`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md)
stops when `src/` already holds such sources, because the generated
build would not compile them. With `mixed = TRUE`, R compiles them with
its own compilers next to the Zig library, and `src/entry.c` leaves
`R_init_<pkg>` to the package, whose own init function registers its
routines with `rzig_register()`, which adds the Zig routines:

``` r

mixed <- file.path(root, "mixedpkg")
dir.create(file.path(mixed, "src"), recursive = TRUE)
writeLines(c("Package: mixedpkg", "Version: 0.0.1"), file.path(mixed, "DESCRIPTION"))
writeLines(c(
  "#include <Rinternals.h>",
  "SEXP legacy_twice(SEXP x) { return Rf_ScalarReal(2 * Rf_asReal(x)); }"
), file.path(mixed, "src", "legacy.c"))
try(use_rzig(mixed))
#> Error : src/ contains compiled sources that the rzig build does not compile: legacy.c. use_rzig(path, mixed = TRUE) or use_rzig_mixed(path) builds them with R's compilers next to the Zig code; the package's R_init_mixedpkg() then calls rzig_register()
use_rzig(mixed, mixed = TRUE)
#> Generated RZig bindings for mixedpkg: 1 exported function
#> Created RZig scaffold for package mixedpkg
writeLines(c(
  "#include <R_ext/Rdynload.h>",
  "#include <Rinternals.h>",
  "SEXP legacy_twice(SEXP x);",
  "void rzig_register(DllInfo *dll, const R_CMethodDef *c_methods,",
  "                   const R_CallMethodDef *call_methods,",
  "                   const R_FortranMethodDef *fortran_methods,",
  "                   const R_ExternalMethodDef *external_methods);",
  "static const R_CallMethodDef call_methods[] = {",
  "    {\"legacy_twice\", (DL_FUNC) &legacy_twice, 1},",
  "    {NULL, NULL, 0}",
  "};",
  "void R_init_mixedpkg(DllInfo *dll) {",
  "    rzig_register(dll, NULL, call_methods, NULL, NULL);",
  "}"
), file.path(mixed, "src", "init.c"))
status <- rzig_status(mixed)
status[status$step == "Scaffold", ]
#> RZig status of package mixedpkg
#>   [ok] Scaffold      build files and framework sources present
#>                      compiled by R's compilers (Config/rzig/mixed):
#>                        src/init.c, src/legacy.c
```

## A C library compiled by Zig

A package can ship the sources of a C library and list it in
`src/rzig/c_libraries.zon`. Zig compiles the sources into the package
and translates the header into a Zig module; nothing is downloaded:

``` r
clib <- file.path(root, "clibpkg")
create_rzig_package(clib, tests = FALSE)
Created package clibpkg at /tmp/RtmpxRUiPx/sharing/clibpkg
Write Zig functions in src/rzig/src/main.zig, then run rzig::document(path) and rzig::build_zig(path)
vendor <- file.path(clib, "src", "rzig", "vendor", "smooth")
dir.create(vendor, recursive = TRUE)
writeLines("double smooth3(double a, double b, double c);", file.path(vendor, "smooth.h"))
writeLines(c(
  "#include \"smooth.h\"",
  "double smooth3(double a, double b, double c) { return (a + 2 * b + c) / 4; }"
), file.path(vendor, "smooth.c"))
writeLines(c(
  ".{",
  "    .{",
  "        .name = \"smooth\",",
  "        .header = \"vendor/smooth/smooth.h\",",
  "        .sources = .{\"vendor/smooth/smooth.c\"},",
  "        .include = .{\"vendor/smooth\"},",
  "    },",
  "}"
), file.path(clib, "src", "rzig", "c_libraries.zon"))
writeLines(c(header,
  "const smooth = @import(\"smooth\");",
  "",
  "/// Smooth a vector with the weights 1, 2, 1 of the C library.",
  "/// @param x A numeric vector.",
  "/// @return A numeric vector.",
  "/// @export",
  "pub fn smoothed(ctx: *rzig.Ctx, x: []const f64) rzig.Error![]f64 {",
  "    const out = try ctx.alloc(f64, x.len);",
  "    for (out, 0..) |*slot, i| {",
  "        const left = x[if (i == 0) 0 else i - 1];",
  "        const right = x[@min(i + 1, x.len - 1)];",
  "        slot.* = smooth.smooth3(left, x[i], right);",
  "    }",
  "    return out;",
  "}"
), file.path(clib, "src", "rzig", "src", "main.zig"))
document(clib)
Generated RZig bindings for clibpkg: 1 exported function
```

``` r

built <- build_zig(clib, lib = lib)
built$ok
#> [1] TRUE
smoothed <- getExportedValue(loadNamespace(built$package, lib.loc = lib), "smoothed")
smoothed(c(0, 4, 0, 4))
#> [1] 1 2 2 3
```

## A Zig module shared between packages

A package shares Zig code as a module, `inst/zig/<module>/root.zig`,
which R installs with it. Another package imports the module:
[`use_rzig_import()`](https://marekdejauj.github.io/rzig/reference/use_rzig_import.md)
names it in `Config/rzig/imports` and the providing package in
`LinkingTo`, so that R installs the provider first. The importing
package compiles the module, so the two packages share no code when they
run:

``` r
provider <- file.path(root, "kernelpkg")
create_rzig_package(provider, tests = FALSE)
Created package kernelpkg at /tmp/RtmpxRUiPx/sharing/kernelpkg
Write Zig functions in src/rzig/src/main.zig, then run rzig::document(path) and rzig::build_zig(path)
use_rzig_module(provider, "kernels")
Package kernelpkg provides the Zig module kernels in inst/zig/kernels/root.zig
cat(readLines(file.path(provider, "inst", "zig", "kernels", "root.zig")), sep = "\n")
//! The Zig module `kernels` of package kernelpkg. Other packages import it with
//! rzig::use_rzig_import(path, "kernelpkg", "kernels") and `@import("kernels")`.

const std = @import("std");

/// The sum of `values`.
pub fn sum(values: []const f64) f64 {
    var total: f64 = 0;
    for (values) |value| total += value;
    return total;
}

test "sum" {
    try std.testing.expectEqual(@as(f64, 6), sum(&.{ 1, 2, 3 }));
}
consumer <- file.path(root, "userpkg")
create_rzig_package(consumer, tests = FALSE)
Created package userpkg at /tmp/RtmpxRUiPx/sharing/userpkg
Write Zig functions in src/rzig/src/main.zig, then run rzig::document(path) and rzig::build_zig(path)
use_rzig_import(consumer, "kernelpkg", "kernels")
Package userpkg imports the Zig module kernels of package kernelpkg
writeLines(c(header,
  "const kernels = @import(\"kernels\");",
  "",
  "/// Twice the sum, by the module of kernelpkg.",
  "/// @param x A numeric vector.",
  "/// @return A number.",
  "/// @export",
  "pub fn twice_sum(x: []const f64) f64 {",
  "    return 2 * kernels.sum(x);",
  "}"
), file.path(consumer, "src", "rzig", "src", "main.zig"))
document(consumer)
Generated RZig bindings for userpkg: 1 exported function
read.dcf(file.path(consumer, "DESCRIPTION"), fields = c("LinkingTo", "Config/rzig/imports"))
     LinkingTo   Config/rzig/imports
[1,] "kernelpkg" "kernelpkg/kernels"
```

``` r

old_paths <- .libPaths()
.libPaths(c(lib, old_paths))
build_zig(provider, lib = lib)$ok
#> [1] TRUE
consumer_build <- build_zig(consumer, lib = lib)
consumer_build$ok
#> [1] TRUE
twice_sum <- getExportedValue(loadNamespace(consumer_build$package, lib.loc = lib), "twice_sum")
twice_sum(c(1, 2, 3))
#> [1] 12
.libPaths(old_paths)
```

## C-callable functions

Compiled code of other packages can call functions that a package
registers with `R_RegisterCCallable()`. The root Zig file lists them,
each with `callconv(.c)`, and may declare an interface version, which
callers check because R checks neither signatures nor versions:

``` r
callee <- file.path(root, "calleepkg")
create_rzig_package(callee, tests = FALSE)
Created package calleepkg at /tmp/RtmpxRUiPx/sharing/calleepkg
Write Zig functions in src/rzig/src/main.zig, then run rzig::document(path) and rzig::build_zig(path)
writeLines(c(header,
  "fn clamp(x: f64, low: f64, high: f64) callconv(.c) f64 {",
  "    return @min(@max(x, low), high);",
  "}",
  "",
  "pub const rzig_callables = .{ .clamp = clamp };",
  "pub const rzig_interface_version: u32 = 1;",
  "",
  "/// The interface version of the C-callable functions.",
  "/// @return An integer.",
  "/// @export",
  "pub fn callee_interface() i32 {",
  "    return 1;",
  "}"
), file.path(callee, "src", "rzig", "src", "main.zig"))
document(callee)
Generated RZig bindings for calleepkg: 1 exported function
caller <- file.path(root, "callerpkg")
create_rzig_package(caller, tests = FALSE)
Created package callerpkg at /tmp/RtmpxRUiPx/sharing/callerpkg
Write Zig functions in src/rzig/src/main.zig, then run rzig::document(path) and rzig::build_zig(path)
writeLines(c(header,
  "const Clamp = fn (f64, f64, f64) callconv(.c) f64;",
  "",
  "/// Clamp values with the function of calleepkg.",
  "/// @param x A numeric vector.",
  "/// @return A numeric vector.",
  "/// @export",
  "pub fn clamped(ctx: *rzig.Ctx, x: []const f64) rzig.Error![]f64 {",
  "    const clamp = try rzig.callable(ctx, Clamp, \"calleepkg\", \"clamp\", .{ .interface = 1 });",
  "    const out = try ctx.alloc(f64, x.len);",
  "    for (x, out) |value, *slot| slot.* = clamp(value, 0, 1);",
  "    return out;",
  "}"
), file.path(caller, "src", "rzig", "src", "main.zig"))
document(caller)
Generated RZig bindings for callerpkg: 1 exported function
```

``` r

old_paths <- .libPaths()
.libPaths(c(lib, old_paths))
build_zig(callee, lib = lib)$ok
#> [1] TRUE
caller_build <- build_zig(caller, lib = lib)
caller_build$ok
#> [1] TRUE
clamped <- getExportedValue(loadNamespace(caller_build$package, lib.loc = lib), "clamped")
clamped(c(-1, 0.5, 2))
#> [1] 0.0 0.5 1.0
.libPaths(old_paths)
```

`rzig.callable()` loads the namespace of the providing package, which
`R_GetCCallable()` does not do; the calling package lists the provider
in `Imports`.
