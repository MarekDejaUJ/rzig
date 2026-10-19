# Locate a supported Zig compiler

Uses the compiler named by the environment variable `ZIG` when it is
set. Otherwise searches the `PATH`, the installations of
[`install_zig()`](https://marekdejauj.github.io/rzig/reference/install_zig.md)
in
[`zig_home()`](https://marekdejauj.github.io/rzig/reference/install_zig.md),
`~/.local/share/zig/*/zig` and `~/zig/zig`, in that order, and reports
the first compiler of a supported release series; when none is
supported, it reports the first compiler found and why it is rejected.
rzig itself runs without Zig:
[`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md),
[`scan_exports()`](https://marekdejauj.github.io/rzig/reference/scan_exports.md)
and
[`document()`](https://marekdejauj.github.io/rzig/reference/document.md)
are pure R. A Zig compiler of the supported release series is needed to
install a package created with
[`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md).

## Usage

``` r
find_zig(required = TRUE)
```

## Arguments

- required:

  If `TRUE`, a missing or unsupported compiler is an error. If `FALSE`,
  the returned object records the problem instead.

## Value

An object of class `rzig_compiler`: a list with `path` (character or
`NULL`), `version` (character or `NULL`), `supported` (logical) and
`series` (the supported release series, `"0.16.x or 0.17.x"`).

## Details

rzig supports the Zig 0.16 and 0.17 release series (versions `0.16.x`
and `0.17.x`). Zig changes its language and standard library between
release series, so a newer or older compiler is reported as unsupported.
Development builds such as `0.17.0-dev.1234+abcdef` are unsupported too:
their language and standard library can differ from the release.

## Examples

``` r
find_zig(required = FALSE)
#> Zig compiler: /home/runner/work/_temp/0beafb3f-08c9-475d-9a85-dbeb3ad24ddb/zig-x86_64-linux-0.16.0/zig (version 0.16.0, supported)
#> rzig supports Zig 0.16.x or 0.17.x.
```
