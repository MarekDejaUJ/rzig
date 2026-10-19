# Update the rzig framework and build files of a package

Brings a package created with
[`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md)
to the installed version of rzig without touching the package author's
work:

## Usage

``` r
update_rzig(path, force = FALSE)
```

## Arguments

- path:

  Path to a package previously initialized with
  [`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md).

- force:

  If `TRUE`, also replace customized build files with the templates of
  the installed rzig.

## Value

An object of class `rzig_update`: a list with `path`, `package`,
`actions` (a data frame with the columns `file` and `action`, one of
`"refreshed"`, `"updated"`, `"added"`, `"removed"`, `"kept"`
(customized), `"replaced"` (customized, with `force = TRUE`) or
`"current"`), `unknown` (files under `src/rzig/framework` that rzig does
not ship) and `exports`, invisibly.

## Details

- the framework sources under `src/rzig/framework` are replaced by those
  of the installed rzig (the generated manifest is rewritten by
  [`document()`](https://marekdejauj.github.io/rzig/reference/document.md));

- each build file (`configure`, `configure.win`, `cleanup`,
  `cleanup.win`, `src/Makevars.in`, `src/Makevars.win.in`,
  `src/entry.c`, `src/rzig/build.zig`, `src/rzig/build.zig.zon` and
  `src/rzig/tools/repack_macos_archive.sh`) is replaced only when it is
  identical to a template shipped by some version of rzig, that is, when
  the package author has not changed it. A changed (customized) build
  file is kept and listed, so that its differences from the new template
  can be reviewed; `force = TRUE` replaces it as well;

- missing build files are added, and the Zig scanner that rzig 0.2
  copied into `src/rzig/tools/scan.zig` is removed;

- the package author's Zig sources in `src/rzig/src`, the list of C
  libraries `src/rzig/c_libraries.zon` (added when missing) and any file
  rzig does not know are never changed or removed;

- finally
  [`document()`](https://marekdejauj.github.io/rzig/reference/document.md)
  regenerates the bindings.

## Examples

``` r
package_path <- tempfile("rzig-update-", tmpdir = tempdir())
dir.create(package_path)
writeLines(c("Package: examplepkg", "Version: 0.0.1"),
  file.path(package_path, "DESCRIPTION"))
use_rzig(package_path)
#> Generated RZig bindings for examplepkg: 1 exported function
#> Created RZig scaffold for package examplepkg
# A customized build file is kept.
cat("# package-specific setting\n",
  file = file.path(package_path, "src", "Makevars.in"), append = TRUE)
update_rzig(package_path)
#> Generated RZig bindings for examplepkg: 1 exported function
#> Updated RZig in package examplepkg to rzig 1.0.0
unlink(package_path, recursive = TRUE)
```
