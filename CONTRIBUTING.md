# Contributing to rzig

rzig generates the native boundary between R and Zig, so a change can affect
every package that uses it. The repository therefore checks each change at
several levels, and a pull request is expected to pass all of them.

## Setting up

- R 4.6 or newer with the build tools of your platform.
- Zig 0.16.0 and 0.17.0 (both series are supported; `rzig::install_zig()`
  installs a verified release).
- The R packages in `Suggests` of `DESCRIPTION`.

## Where things live

- `src/` is the Zig framework. `sh tools/sync_fixture.sh` and
  `sh tools/sync_r_package_assets.sh` copy it into the test fixture, the
  example package and `inst/zig/framework`; `zig build gen` regenerates the
  generated Zig files. Edit `src/`, never the copies.
- `R/` is the R package: scanning, rendering, checks, the build and the
  helpers. `inst/templates` and `inst/zig` are the templates that `use_rzig()`
  copies into packages.
- `tests/fixtures/rzigtest` is an R package that exercises the boundary;
  `examples/rzigcausal` is an example package built in CI.

## Checks before a pull request

```sh
zig build test            # Zig unit tests, with Zig 0.16 and 0.17
zig build lint            # the one-error-exit and jump-resume rules
sh tools/sync_fixture.sh --check
zig fmt --check build.zig src tools tests/fixtures/rzigtest/src/rzig examples/rzigcausal/src/rzig
```

```r
devtools::test()          # with NOT_CRAN=true; builds packages when Zig is present
devtools::check()
```

The fixture tests run in an installed copy of `tests/fixtures/rzigtest`
(see `.github/workflows/ci.yml` for the commands), and
`Rscript tools/gctorture_run.R tests/gctorture-callbacks.R` runs the
boundary under `gctorture()`.

## Rules for the boundary

- Zig code returns errors; only `src/boundary.zig` raises R errors, after
  every Zig resource has been released (`zig build lint` enforces it).
- R code runs only on the thread that entered R, and R's jumps out of R code
  that Zig calls are stopped before the Zig frames (`src/rcall.zig`).
- Every R API symbol that `src/c/abi.zig` declares must be part of R's API
  (`Rscript tools/check_api_symbols.R`).
- A change that affects packages gets a NEWS entry, and a change of a
  template keeps `update_rzig()` working (`Rscript tools/known_template_hashes.R`).

## Reporting problems

Please use the issue templates: a bug report names the versions of R, rzig
and Zig and the platform, and includes `rzig::rzig_status(path)` of the
package and a minimal Zig function that shows the problem.

## License

By contributing, you agree that your contributions are licensed under the
GNU General Public License, version 3, the license of rzig.
