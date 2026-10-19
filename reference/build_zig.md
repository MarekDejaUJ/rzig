# Compile and install a Zig-backed package, and report the first errors

Runs the checks of
[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md),
then installs a copy of the package with `R CMD INSTALL` into a library,
using the Zig compiler reported by
[`find_zig()`](https://marekdejauj.github.io/rzig/reference/find_zig.md).
The complete installation log is kept, and the errors of the Zig
compiler, the C compiler, the linker and the load test are extracted
with their files and lines, so a failed build names its cause instead of
the bare "non-zero exit status" of
[`utils::install.packages()`](https://rdrr.io/r/utils/install.packages.html).

## Usage

``` r
build_zig(
  path,
  lib = NULL,
  preflight = TRUE,
  optimize = Sys.getenv("RZIG_OPTIMIZE", "ReleaseSafe")
)
```

## Arguments

- path:

  Path to the package root.

- lib:

  The library to install into. By default a new library in the session
  temporary directory;
  [`library()`](https://rdrr.io/r/base/library.html) then needs
  `lib.loc = build$library`.

- preflight:

  If `TRUE`, run the checks of
  [`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
  first and stop before compiling when one of them fails.

- optimize:

  The optimize mode of the Zig code: `"ReleaseSafe"` (optimized, with
  Zig's safety checks) or `"Debug"` (unoptimized, with the same safety
  checks and complete stack traces, for debugging). The default is the
  environment variable `RZIG_OPTIMIZE`, which the generated Makevars
  also read, or `"ReleaseSafe"`. The modes without safety checks
  (`ReleaseFast`, `ReleaseSmall`) are not available, because the
  boundary turns failed checks into R errors; `@setRuntimeSafety(false)`
  removes the checks of a single function.

## Value

An object of class `rzig_build`: a list with `ok` (logical), `package`,
`step` (`"preflight"`, `"configure"`, `"compile"`, `"link"`, `"load"`,
`"install"` or `NA` on success), `errors` (a data frame with the columns
`file`, `line`, `column`, `message` and `function_name`), `problems`
(failed checks before compilation), `library`, `zig` (the
[rzig_compiler](https://marekdejauj.github.io/rzig/reference/find_zig.md)
used), `optimize`, `seconds` and `log` (the complete output of
`R CMD INSTALL`). A failed build also signals a warning.

## Details

The package is built from a copy in the session temporary directory, so
the package source receives no object files or compiler caches. The
installation needs a supported Zig compiler and the C toolchain of R. A
package that is already loaded in the R session keeps its old native
code until R restarts; the printed result says so.

## Examples

``` r
package_path <- tempfile("rzig-build-", tmpdir = tempdir())
dir.create(package_path)
writeLines(c("Package: examplepkg", "Version: 0.0.1"),
  file.path(package_path, "DESCRIPTION"))
use_rzig(package_path)
#> Generated RZig bindings for examplepkg: 1 exported function
#> Created RZig scaffold for package examplepkg

# A change to main.zig without document() is caught before compiling.
main <- file.path(package_path, "src", "rzig", "src", "main.zig")
cat("/// @export\npub fn twice(x: f64) f64 {\n    return 2 * x;\n}\n",
  file = main, append = TRUE)
result <- suppressWarnings(build_zig(package_path))
result
#> Build of package examplepkg: not started; checks before compilation failed
#>   Bindings: out of date: manifest.zig, R/rzig-wrappers.R, NAMESPACE,
#>     man/twice.Rd; run document()

# With a supported Zig compiler, the regenerated package compiles; the
# compilation takes several seconds.
# \donttest{
if (isTRUE(find_zig(required = FALSE)$supported)) {
  document(package_path)
  result <- build_zig(package_path)
  result
}
#> Generated RZig bindings for examplepkg: 2 exported functions
#> Build of package examplepkg: succeeded in 11.9 seconds
#> Zig compiler: /home/runner/work/_temp/0beafb3f-08c9-475d-9a85-dbeb3ad24ddb/zig-x86_64-linux-0.16.0/zig (version 0.16.0)
#> Installed into a library in the session temporary directory
# }
unlink(package_path, recursive = TRUE)
```
