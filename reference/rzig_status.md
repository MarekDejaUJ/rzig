# Report the state of a Zig-backed package

Checks each step of the RZig workflow in a package and reports what is
present, what is missing and what would make the installation fail:

## Usage

``` r
rzig_status(path, build = FALSE, lib = NULL)
```

## Arguments

- path:

  Path to the package root.

- build:

  If `TRUE`, also compile and install the package with
  [`build_zig()`](https://marekdejauj.github.io/rzig/reference/build_zig.md)
  when every other check passes.

- lib:

  With `build = TRUE`, the library to install into; see
  [`build_zig()`](https://marekdejauj.github.io/rzig/reference/build_zig.md).

## Value

An object of class `rzig_status`: a data frame with the columns `step`,
`ok` and `detail`, one row per check, with the attributes `path`,
`package` and, with `build = TRUE`, `build` (the
[rzig_build](https://marekdejauj.github.io/rzig/reference/build_zig.md)
object).

## Details

- **DESCRIPTION**: the package name and a valid version.

- **Scaffold**: the files written by
  [`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md),
  framework sources that match the installed rzig, and executable
  `configure` and `cleanup` scripts. Build files that differ from the
  rzig templates (`configure`, the Makevars, `entry.c`, `build.zig`,
  `build.zig.zon`, `tools/`) are noted, since a package may extend them.

- **Zig source**: `src/rzig/src/main.zig` with the registration block
  and the panic handler of rzig.

- **Exports**: the exported functions found by
  [`scan_exports()`](https://marekdejauj.github.io/rzig/reference/scan_exports.md),
  with every argument and return type that the boundary rejects, more
  than 32 arguments, misuse of `rzig.Mut([]f64)`, error sets other than
  `rzig.Error`, and R functions of the same name elsewhere in `R/`. An
  export that masks a function of base R (for example `log`) is noted.

- **Bindings**: whether the files written by
  [`document()`](https://marekdejauj.github.io/rzig/reference/document.md)
  match the exports.

- **Zig compiler**: a compiler of a supported release series
  ([`find_zig()`](https://marekdejauj.github.io/rzig/reference/find_zig.md)).

- **C toolchain**: the C compiler of R, `make` and the R headers.

- **Build** (only with `build = TRUE`): the result of
  [`build_zig()`](https://marekdejauj.github.io/rzig/reference/build_zig.md).

Every check except the build runs in R without compiling anything.

## Examples

``` r
package_path <- tempfile("rzig-status-", tmpdir = tempdir())
dir.create(package_path)
writeLines(c("Package: examplepkg", "Version: 0.0.1"),
  file.path(package_path, "DESCRIPTION"))
use_rzig(package_path)
#> Generated RZig bindings for examplepkg: 1 exported function
#> Created RZig scaffold for package examplepkg
rzig_status(package_path)
#> RZig status of package examplepkg
#>   [ok] DESCRIPTION   package examplepkg
#>                      R CMD check also requires Title, Description, License,
#>                        Authors@R
#>                      SystemRequirements does not name Zig; state the
#>                        supported series, for example "Zig 0.16.x or 0.17.x"
#>   [ok] Scaffold      build files and framework sources present
#>   [ok] Zig source    src/rzig/src/main.zig
#>   [ok] Exports       1 function: hello_zig
#>   [ok] Bindings      generated files match the exports
#>   [ok] Zig compiler  /home/runner/work/_temp/9e0fe227-0da4-4767-900a-44012cf37f43/zig-x86_64-linux-0.16.0/zig
#>                        (version 0.16.0)
#>   [ok] C toolchain   C compiler gcc
main <- file.path(package_path, "src", "rzig", "src", "main.zig")
cat("/// @export\npub fn half(x: f32) f32 {\n    return x / 2;\n}\n",
  file = main, append = TRUE)
rzig_status(package_path)
#> RZig status of package examplepkg
#>   [ok] DESCRIPTION   package examplepkg
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
#>   [ok] Zig compiler  /home/runner/work/_temp/9e0fe227-0da4-4767-900a-44012cf37f43/zig-x86_64-linux-0.16.0/zig
#>                        (version 0.16.0)
#>   [ok] C toolchain   C compiler gcc
#> 2 of 7 checks failed: Exports, Bindings
unlink(package_path, recursive = TRUE)
```
