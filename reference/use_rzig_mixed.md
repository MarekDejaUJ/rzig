# Build C, C++ and Fortran sources next to the Zig code

Adds `Config/rzig/mixed: true` to `DESCRIPTION`. The generated
`configure` then leaves `OBJECTS` unset, so that R compiles every C, C++
and Fortran source file of `src/` with its own compilers and links them
with the Zig library, and `src/entry.c` leaves `R_init_<pkg>` to the
package. The package's `R_init_<pkg>` registers its own routines with
`rzig_register()`, which adds the Zig routines to the `.Call` routines:

## Usage

``` r
use_rzig_mixed(path)
```

## Arguments

- path:

  Path to the package root.

## Value

The path of `DESCRIPTION`, invisibly.

## Details

    #include <R_ext/Rdynload.h>

    void rzig_register(DllInfo *dll, const R_CMethodDef *c_methods,
                       const R_CallMethodDef *call_methods,
                       const R_FortranMethodDef *fortran_methods,
                       const R_ExternalMethodDef *external_methods);

    static const R_CallMethodDef call_methods[] = {
        {"legacy_add", (DL_FUNC) &legacy_add, 2},
        {NULL, NULL, 0}
    };

    void R_init_mypkg(DllInfo *dll) {
        rzig_register(dll, NULL, call_methods, NULL, NULL);
    }

Dynamic symbol lookup stays disabled; the R code may name the routines
by symbol or by string. A C routine with the name of a Zig export is not
registered (a message says so when the package loads).
[`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md)
with `mixed = TRUE` calls this function before it scaffolds the package.

## Examples

``` r
package_path <- tempfile("rzig-mixed-", tmpdir = tempdir())
dir.create(package_path)
writeLines(c("Package: examplepkg", "Version: 0.0.1"),
  file.path(package_path, "DESCRIPTION"))
use_rzig_mixed(package_path)
#> Package examplepkg builds its C, C++ and Fortran sources next to the Zig code
read.dcf(file.path(package_path, "DESCRIPTION"), fields = "Config/rzig/mixed")
#>      Config/rzig/mixed
#> [1,] "true"           
unlink(package_path, recursive = TRUE)
```
