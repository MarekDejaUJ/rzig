# Distributing a package that uses RZig

A package that uses RZig is a source package with compiled code: whoever
installs it from source needs R’s build tools and a Zig compiler of the
supported series (0.16 or 0.17). rzig itself is pure R and needs no
compiler. This vignette describes what a package states about Zig, how
users obtain the compiler, and the channels through which such a package
reaches its users. The code is plain R.

## What the package states

[`create_rzig_package()`](https://marekdejauj.github.io/rzig/reference/create_rzig_package.md)
and
[`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md)
write the field that names the compiler, and
[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
notes a `DESCRIPTION` without it:

``` r

path <- file.path(tempdir(), "distpkg")
create_rzig_package(path, tests = FALSE)
#> Created package distpkg at /tmp/RtmpbmQ3hi/distpkg
#> Write Zig functions in src/rzig/src/main.zig, then run rzig::document(path) and rzig::build_zig(path)
read.dcf(file.path(path, "DESCRIPTION"), fields = "SystemRequirements")
#>      SystemRequirements    
#> [1,] "Zig 0.16.x or 0.17.x"
```

`configure` reports the compiler it uses in the installation log and
rejects other versions with a message that names the version it found,
and the Zig build uses at most two jobs, as CRAN’s policy for compiled
code asks.

## How users get Zig

[`find_zig()`](https://marekdejauj.github.io/rzig/reference/find_zig.md)
reports the compiler that an installation would use. A user without one
installs a verified release with
[`install_zig()`](https://marekdejauj.github.io/rzig/reference/install_zig.md),
which asks for permission, downloads the archive of a pinned release,
checks its SHA-256 checksum and keeps it in the user cache folder of
rzig, where `configure` finds it:

``` r

find_zig(required = FALSE)
#> Zig compiler: /home/runner/work/_temp/9e0fe227-0da4-4767-900a-44012cf37f43/zig-x86_64-linux-0.16.0/zig (version 0.16.0, supported)
#> rzig supports Zig 0.16.x or 0.17.x.
```

Alternatives are a download from <https://ziglang.org/download/>, with
the compiler on `PATH` or named by `ZIG`, or `RZIG_DOWNLOAD_ZIG=true` in
the environment of the installation, with which `configure` downloads
and checks the same pinned release itself when it finds no compiler.

## GitHub and r-universe

`remotes::install_github()` and
[`pak::pak()`](https://pak.r-lib.org/reference/pak.html) build the
package from source on the user’s machine, so the user needs Zig as
above. r-universe builds binary packages for Windows and macOS on its
own machines, which have no Zig; a package for r-universe or GitHub can
ask `configure` to download the pinned release into its build folder
when no compiler is found:

``` r

cat("Config/rzig/download-zig: true\n", file = file.path(path, "DESCRIPTION"), append = TRUE)
status <- rzig_status(path)
status[status$step == "DESCRIPTION", ]
#> RZig status of package distpkg
#>   [ok] DESCRIPTION   package distpkg
#>                      Config/rzig/download-zig: configure downloads a verified
#>                        Zig when it finds none; CRAN does not allow that without
#>                        its consent, so a package for CRAN leaves the field out
```

The download goes to `src/rzig/.zig-download`, which the build excludes
from the package and `cleanup` removes. Users of binary packages need no
compiler at all.

## CRAN

CRAN’s build machines have no Zig compiler, and CRAN’s policy forbids
downloading a compiler during the installation without the agreement of
the CRAN team, so `Config/rzig/download-zig` is not for packages on
CRAN. A package for CRAN states Zig in `SystemRequirements`, as packages
with Rust code state Cargo; whether CRAN builds such packages depends on
CRAN providing the compiler. rzig itself is on CRAN because its checks
compile no Zig code.

## Continuous integration

[`use_rzig_ci()`](https://marekdejauj.github.io/rzig/reference/use_rzig_ci.md)
writes a GitHub Actions workflow that installs Zig 0.16 and 0.17 and
runs `R CMD check` with the settings that CRAN applies to compiled code
on Linux, macOS and Windows:

``` r

use_rzig_ci(path)
#> Wrote .github/workflows/rzig-check.yaml for package distpkg
file.exists(file.path(path, ".github", "workflows", "rzig-check.yaml"))
#> [1] TRUE
```
