# Add a GitHub Actions workflow that checks the package with Zig

Writes `.github/workflows/rzig-check.yaml`, a workflow that installs R
and Zig and runs `R CMD check --as-cran` on each operating system and
Zig version of its matrix. When `src/rzig/src/tests.zig` exists, the Zig
tests
([`test_zig()`](https://marekdejauj.github.io/rzig/reference/test_zig.md))
run before the check. `.github` is added to `.Rbuildignore`.

## Usage

``` r
use_rzig_ci(
  path,
  zig = c("0.16.0", "0.17.0"),
  os = c("ubuntu-latest", "macos-latest", "windows-latest"),
  overwrite = FALSE
)
```

## Arguments

- path:

  Path to a package previously initialized with
  [`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md).

- zig:

  The Zig versions to test: releases of the series rzig supports (see
  [`find_zig()`](https://marekdejauj.github.io/rzig/reference/find_zig.md)).

- os:

  The GitHub runners to test on.

- overwrite:

  If `TRUE`, replace an existing workflow file.

## Value

The path of the workflow file, invisibly.

## Examples

``` r
package_path <- tempfile("rzig-ci-", tmpdir = tempdir())
dir.create(package_path)
writeLines(c("Package: examplepkg", "Version: 0.0.1"),
  file.path(package_path, "DESCRIPTION"))
use_rzig(package_path)
#> Generated RZig bindings for examplepkg: 1 exported function
#> Created RZig scaffold for package examplepkg
use_rzig_ci(package_path, os = "ubuntu-latest")
#> Wrote .github/workflows/rzig-check.yaml for package examplepkg
unlink(package_path, recursive = TRUE)
```
