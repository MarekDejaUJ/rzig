# Scan the Zig source of a package for exported functions

Reads `src/rzig/src/main.zig`, and every Zig file that it imports with
`pub const name = @import("file.zig");` (recursively), and lists every
public top-level Zig function whose documentation comment contains a
line `/// @export`. A function of an imported file is registered as
`name.function`; its R name is the function name. `/// @export` above
`pub const twice = other.twice;` re-exports a function of a file
imported as `other` under the name `twice`. A file imported with a plain
`const` cannot be reached by the generated registration, so a marker in
it is an error; a marked file that is not imported at all is ignored,
and
[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
notes it. R names must be unique across all files.

## Usage

``` r
scan_exports(path)
```

## Arguments

- path:

  Path to a package previously initialized with
  [`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md).

## Value

An object of class `rzig_exports`: a list with one element per exported
function, each a list with `name` (the R function name), `identifier`
(the Zig identifier as written), `parameters` (the R argument names),
`parameter_types` (the Zig types of the R arguments), `return_type` (the
Zig return type as written), `doc` (the documentation comment without
the `@export` line), `line` (the line of the declaration), `internal`
(`TRUE` for `/// @export internal`) and `file` (the file below
`src/rzig/src`), `invisible` and `defaults` (a named character vector of
R expressions). The attributes `package`, `path`, `source` (the entry
file), `files` (every file scanned) and `unreachable` (marked files that
`main.zig` does not import) record where the exports come from.
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) turns the
object into a table with one row per function.

## Details

The marker line takes options: `/// @export internal` registers the
function without exporting its R wrapper, `/// @export invisible` makes
the wrapper return its value invisibly, and `/// @export name=<R name>`
gives the wrapper an R name other than the Zig name. Lines
`/// @default <argument> <R expression>` give default arguments of the
wrapper, for example `/// @default tolerance 1e-8`. A line
`/// @export internal` registers the function and generates its R
wrapper without exporting the wrapper from the package, for native
routines that the package's own R code calls. The scan is pure R and
needs no Zig compiler; the Zig compiler checks the parameter and return
types when the package is installed.

A struct whose documentation comment contains `/// @class` becomes an R
class: its `pub fn init` is the constructor, exported under the name of
the struct, and every public function whose first parameter is the
struct (`self: *T`, `self: *const T` or `self: T`) is a method,
registered as the internal routine `T_method` and called as
`x$method(...)` on an object `x`. Objects are rzig.External values (see
the README); `deinit`, when declared, runs when R collects the object.

A function is found when its declaration starts at the beginning of a
line with `pub fn` and the lines directly above it are `///`
documentation comments (blank lines and ordinary `//` comments between
the comment block and the declaration are ignored). The first parameter
is omitted from the R signature when its type is `*rzig.Ctx`.

## Examples

``` r
package_path <- tempfile("rzig-scan-", tmpdir = tempdir())
dir.create(package_path)
writeLines(c("Package: examplepkg", "Version: 0.0.1"),
  file.path(package_path, "DESCRIPTION"))
use_rzig(package_path)
#> Generated RZig bindings for examplepkg: 1 exported function
#> Created RZig scaffold for package examplepkg
exports <- scan_exports(package_path)
exports
#> Zig exports of package examplepkg (src/rzig/src/main.zig): 1 function
#> 
#> hello_zig(name)
#>   name       []const u8             character, length 1, copied
#>   returns    rzig.Error![]const u8  character, length 1
as.data.frame(exports)
#>        name arguments           return_type documented internal line
#> 1 hello_zig      name rzig.Error![]const u8       TRUE    FALSE   17
unlink(package_path, recursive = TRUE)
```
