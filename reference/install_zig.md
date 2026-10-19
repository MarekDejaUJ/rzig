# Download and install a supported Zig compiler

Downloads the Zig release `version` for this platform, verifies the
archive against the size and SHA-256 that
<https://ziglang.org/download/index.json> publishes (pinned in rzig),
and unpacks it into `dir`.
[`find_zig()`](https://marekdejauj.github.io/rzig/reference/find_zig.md)
and the `configure` scripts of packages created with
[`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md)
find compilers installed in `zig_home()`, so `R CMD INSTALL` of such a
package needs no further setup.

## Usage

``` r
install_zig(
  version = "0.16.0",
  dir = zig_home(),
  mirrors = TRUE,
  quiet = FALSE
)

uninstall_zig(version = NULL, dir = zig_home())

zig_home()
```

## Arguments

- version:

  The Zig release: `"0.16.0"` or `"0.17.0"`.

- dir:

  The folder that holds the installations.

- mirrors:

  If `FALSE`, download from ziglang.org only.

- quiet:

  If `TRUE`, show no download progress.

## Value

`install_zig()`: the path of the zig executable, invisibly.
`uninstall_zig()`: the folders removed, invisibly. `zig_home()`: a path.

## Details

The archive (about 55 MB, about 300 MB unpacked) comes from one of the
community mirrors of Zig, tried in an order that varies between
sessions, or else from ziglang.org, as the Zig Software Foundation asks
of automated downloads. A download whose size or SHA-256 differs from
the pin is deleted before anything is extracted or run. An existing
installation of the same version is reused. `uninstall_zig()` removes
installations made by `install_zig()`.

`zig_home()` is the folder named by the environment variable
`RZIG_ZIG_HOME`, or `zig` in the user cache folder of rzig
([`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html)).

## Examples

``` r
zig_home()
#> [1] "/home/runner/.cache/R/rzig/zig"
if (FALSE) { # \dontrun{
install_zig("0.16.0")
find_zig()
} # }
```
