# Share Zig modules between R packages

A package can share Zig code with other packages as a Zig module: the
file `inst/zig/<module>/root.zig`, with the files it imports from that
folder, installed with the package. `use_rzig_import()` lets the Zig
code of the package at `path` use such a module with
`@import("<module>")`: it adds `<package>/<module>` to the field
`Config/rzig/imports` of `DESCRIPTION` and `<package>` to `LinkingTo`,
so that R installs the providing package first. `configure` finds the
module in the installed package and passes it to `zig build`; the module
can import rzig and the other imported modules. The module is compiled
into the importing package, so nothing is linked between the packages
when they run.

## Usage

``` r
use_rzig_import(path, package, module)

use_rzig_module(path, module, import = TRUE)
```

## Arguments

- path:

  Path to the package root.

- package:

  The name of the package that provides the module.

- module:

  The name of the Zig module, a Zig identifier other than `rzig`, `std`,
  `builtin` and `root`.

- import:

  For `use_rzig_module()`: also import the module in the package's own
  Zig code.

## Value

The path of `DESCRIPTION` (`use_rzig_import()`) or of the module's
`root.zig` (`use_rzig_module()`), invisibly.

## Details

`use_rzig_module()` creates `inst/zig/<module>/root.zig` with a starter
in the providing package and, with `import = TRUE`, imports the module
in the package's own Zig code as well (an entry that names the package
itself refers to its source). It also writes
`inst/include/<package>_rzig.h`, a header without declarations: R CMD
check expects a package in `LinkingTo` to provide an `include`
directory.

## Examples

``` r
provider <- tempfile("rzig-provider-", tmpdir = tempdir())
dir.create(provider)
writeLines(c("Package: kernelpkg", "Version: 0.0.1"), file.path(provider, "DESCRIPTION"))
use_rzig_module(provider, "kernels")
#> Package kernelpkg provides the Zig module kernels in inst/zig/kernels/root.zig
consumer <- tempfile("rzig-consumer-", tmpdir = tempdir())
dir.create(consumer)
writeLines(c("Package: userpkg", "Version: 0.0.1"), file.path(consumer, "DESCRIPTION"))
use_rzig_import(consumer, "kernelpkg", "kernels")
#> Package userpkg imports the Zig module kernels of package kernelpkg
read.dcf(file.path(consumer, "DESCRIPTION"), fields = c("LinkingTo", "Config/rzig/imports"))
#>      LinkingTo   Config/rzig/imports
#> [1,] "kernelpkg" "kernelpkg/kernels"
unlink(c(provider, consumer), recursive = TRUE)
```
