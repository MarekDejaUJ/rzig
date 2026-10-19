# Compile Zig code from the R prompt

`zig_function()` compiles Zig source code into a small package in the
session's temporary directory and defines its exported functions in
`env`, the counterpart of `Rcpp::cppFunction()`. `zig_source()` does the
same for a file, and `zig_eval()` evaluates one Zig expression.

## Usage

``` r
zig_function(code, env = parent.frame(), quiet = TRUE)

zig_source(file, env = parent.frame(), quiet = TRUE)

zig_eval(expr, type = "f64")
```

## Arguments

- code:

  Zig source code, a character vector whose elements are lines.

- env:

  The environment in which the functions are defined.

- quiet:

  If `FALSE`, print the build result.

- file:

  A Zig source file.

- expr:

  A Zig expression, as a string.

- type:

  The Zig type of the value of `expr`, a return type the boundary
  supports (for example `"f64"`, `"i32"`, `"bool"`, `"[]const u8"`).

## Value

`zig_function()` and `zig_source()`: the function, if the code exports
exactly one, otherwise a named list of the functions, invisibly.
`zig_eval()`: the value of the expression.

## Details

The code is placed in a generated `main.zig` after the lines
`const std = @import("std");`, `const builtin = @import("builtin");`,
`const rzig = @import("rzig");` and the panic handler declaration (each
left out when the code declares it), and before the registration block.
Public functions marked `/// @export` are exported; when the code marks
none, every top-level `pub fn` is exported. The types, errors and checks
of the boundary are those of a package
([`scan_exports()`](https://marekdejauj.github.io/rzig/reference/scan_exports.md),
[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)).

Builds are cached for the session by the code, the rzig version and the
Zig compiler: calling `zig_function()` again with the same code defines
the functions without compiling. A failed build is reported with the
lines of `code` and stops with an error.

## Examples

``` r
# \donttest{
if (isTRUE(find_zig(required = FALSE)$supported)) {
  twice <- zig_function("pub fn twice(x: f64) f64 { return 2 * x; }")
  twice(21)
  zig_eval("@sqrt(2.0)", type = "f64")
}
#> [1] 1.414214
# }
```
