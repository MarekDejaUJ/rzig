# Add RZig to a package

Creates the Zig source tree, the portable build files, the native entry
stub and a working `hello_zig()` example in an existing package, then
generates the bindings with
[`document()`](https://marekdejauj.github.io/rzig/reference/document.md).
The function is pure R; a Zig compiler of the supported release series
(see
[`find_zig()`](https://marekdejauj.github.io/rzig/reference/find_zig.md))
is needed only when the package is installed.

## Usage

``` r
use_rzig(path, overwrite = FALSE, force = FALSE, mixed = FALSE)
```

## Arguments

- path:

  Path to the package root; the directory must contain a `DESCRIPTION`
  file.

- overwrite:

  Allow `use_rzig()` on a package that already has RZig files. The
  framework sources and every build file that still matches an rzig
  template are then replaced, as with
  [`update_rzig()`](https://marekdejauj.github.io/rzig/reference/update_rzig.md);
  the package author's Zig sources in `src/rzig/src` and files rzig does
  not know are kept. A build file the package author changed stops the
  call unless `force = TRUE`.
  [`update_rzig()`](https://marekdejauj.github.io/rzig/reference/update_rzig.md)
  is the usual way to update a package: it keeps customized build files
  and lists them.

- force:

  With `overwrite = TRUE`, also replace customized build files with the
  templates.

- mixed:

  Build the C, C++ and Fortran sources of `src/` with R's compilers next
  to the Zig code; see
  [`use_rzig_mixed()`](https://marekdejauj.github.io/rzig/reference/use_rzig_mixed.md).
  Without it, `use_rzig()` stops when `src/` contains such sources.

## Value

An object of class `rzig_scaffold`: a list with `path` (the normalized
package root), `package`, `files` (the paths written, relative to the
root) and `exports` (the
[rzig_exports](https://marekdejauj.github.io/rzig/reference/scan_exports.md)
found in `main.zig`), invisibly.

## Details

The files written below the package root are: `configure`,
`configure.win`, `cleanup`, `cleanup.win`, `src/entry.c`,
`src/Makevars.in`, `src/Makevars.win.in`, the framework sources under
`src/rzig/framework`, the list of vendored C libraries
`src/rzig/c_libraries.zon` (empty), the package author's Zig source
`src/rzig/src/main.zig`, the generated `R/rzig-wrappers.R`, and a
managed block in `NAMESPACE`. Entries for the Zig build caches are added
to `.Rbuildignore`, and the Zig sources are listed in the
`Config/build/extra-sources` field of `DESCRIPTION`, so that
`devtools::load_all()` recompiles the package after a change to a Zig
file.

## Examples

``` r
package_path <- tempfile("rzig-example-", tmpdir = tempdir())
dir.create(package_path)
writeLines(c("Package: examplepkg", "Version: 0.0.1"),
  file.path(package_path, "DESCRIPTION"))
scaffold <- use_rzig(package_path)
#> Generated RZig bindings for examplepkg: 1 exported function
#> Created RZig scaffold for package examplepkg
scaffold
#> RZig scaffold of package examplepkg: 52 files written
#> Zig source: src/rzig/src/main.zig
#> Exported functions: hello_zig
#> Next steps: edit main.zig, run document(), then install the package with a Zig compiler (see find_zig()).
file.exists(file.path(package_path, "src", "rzig", "src", "main.zig"))
#> [1] TRUE
unlink(package_path, recursive = TRUE)
```
