# Link the LAPACK and BLAS libraries of R

Adds `Config/rzig/lapack: true` to `DESCRIPTION`. The generated
`configure` then links `$(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)`, the
libraries that `rzig.Blas` and `rzig.Lapack` call, in the order *Writing
R Extensions* asks for. `$(FLIBS)` is the Fortran runtime of R: on
macOS, installing such a package from source needs the gfortran that
CRAN's R builds use (<https://mac.r-project.org/tools/>), on Windows it
comes with Rtools.

## Usage

``` r
use_rzig_lapack(path)
```

## Arguments

- path:

  Path to a package previously initialized with
  [`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md).

## Value

The path of `DESCRIPTION`, invisibly.

## Examples

``` r
package_path <- tempfile("rzig-lapack-", tmpdir = tempdir())
dir.create(package_path)
writeLines(c("Package: examplepkg", "Version: 0.0.1"),
  file.path(package_path, "DESCRIPTION"))
use_rzig(package_path)
#> Generated RZig bindings for examplepkg: 1 exported function
#> Created RZig scaffold for package examplepkg
use_rzig_lapack(package_path)
#> Package examplepkg links the LAPACK and BLAS of R
read.dcf(file.path(package_path, "DESCRIPTION"), fields = "Config/rzig/lapack")
#>      Config/rzig/lapack
#> [1,] "true"            
unlink(package_path, recursive = TRUE)
```
