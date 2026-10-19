# Updating rzig in a package

A package created with
[`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md)
contains a copy of the rzig framework (`src/rzig/framework`) and build
files made from rzig’s templates (`configure`, `src/Makevars.in`,
`src/entry.c`, `src/rzig/build.zig` and others). The framework and the R
side of rzig must come from the same version, because the generated
bindings rely on both. After an update of rzig,
[`update_rzig()`](https://marekdejauj.github.io/rzig/reference/update_rzig.md)
brings the package to the installed version. Every step of this vignette
is plain R and needs no Zig compiler.

## A package to update

``` r

path <- file.path(tempdir(), "updatedpkg")
create_rzig_package(path, tests = FALSE)
#> Created package updatedpkg at /tmp/RtmpHzdwMC/updatedpkg
#> Write Zig functions in src/rzig/src/main.zig, then run rzig::document(path) and rzig::build_zig(path)
```

## What the update does

[`update_rzig()`](https://marekdejauj.github.io/rzig/reference/update_rzig.md)
replaces the framework sources, replaces each build file that is
identical to a template of some rzig version (the package author has not
changed it), adds missing files and regenerates the bindings. The
package author’s Zig sources in `src/rzig/src`, the list of C libraries
`src/rzig/c_libraries.zon` and every file rzig does not know stay as
they are. On a package that is current, the result lists no file:

``` r

result <- update_rzig(path)
#> Generated RZig bindings for updatedpkg: 1 exported function
#> Updated RZig in package updatedpkg to rzig 1.0.0
result
#> RZig update of package updatedpkg
#>   everything matches the installed rzig
```

## Customized build files are kept

A build file that the package author changed is kept, because the change
may matter, and listed, so that it can be compared with the new
template. Here `src/Makevars.in` gets an extra comment:

``` r

makevars <- file.path(path, "src", "Makevars.in")
cat("# Built with a custom flag.\n", file = makevars, append = TRUE)
result <- update_rzig(path)
#> Generated RZig bindings for updatedpkg: 1 exported function
#> Updated RZig in package updatedpkg to rzig 1.0.0
result
#> RZig update of package updatedpkg
#>   customized build files kept (compare with the templates of rzig) (1):
#>     src/Makevars.in
```

[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
notes the difference without failing, because a customized build file is
allowed:

``` r

status <- rzig_status(path)
status[status$step == "Scaffold", ]
#> RZig status of package updatedpkg
#>   [ok] Scaffold      build files and framework sources present
#>                      differs from the rzig template: src/Makevars.in
```

With `force = TRUE`,
[`update_rzig()`](https://marekdejauj.github.io/rzig/reference/update_rzig.md)
replaces customized build files with the templates as well:

``` r

result <- update_rzig(path, force = TRUE)
#> Generated RZig bindings for updatedpkg: 1 exported function
#> Updated RZig in package updatedpkg to rzig 1.0.0
result
#> RZig update of package updatedpkg
#>   customized build files replaced (1):
#>     src/Makevars.in
```

## A framework from another version

When the framework files differ from those of the installed rzig, for
example after `install.packages("rzig")` in a project that was not
updated,
[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
fails the scaffold step and names
[`update_rzig()`](https://marekdejauj.github.io/rzig/reference/update_rzig.md).
A changed framework file shows the check:

``` r

framework_file <- file.path(path, "src", "rzig", "framework", "rzig.zig")
cat("// local change\n", file = framework_file, append = TRUE)
status <- rzig_status(path)
status[status$step == "Scaffold", ]
#> RZig status of package updatedpkg
#>   [--] Scaffold      1 framework file differs from rzig 1.0.0
#>                        (framework/rzig.zig); run update_rzig(path), which keeps
#>                        src/rzig/src and customized build files
#> 1 of 1 checks failed: Scaffold
result <- update_rzig(path)
#> Generated RZig bindings for updatedpkg: 1 exported function
#> Updated RZig in package updatedpkg to rzig 1.0.0
result
#> RZig update of package updatedpkg
#>   framework sources refreshed (1):
#>     src/rzig/framework/rzig.zig
```

## Recommended routine

After updating rzig: run `update_rzig(path)`, read the list of kept
files, run `rzig_status(path)`, rebuild with `build_zig(path)` and run
the tests of the package. The NEWS file of rzig lists the changes of
each version that affect packages.
