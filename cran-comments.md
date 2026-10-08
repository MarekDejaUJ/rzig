## rzig 0.3.0

Changes since 0.2.3: the workflow is exposed step by step (`find_zig()`,
`scan_exports()`, `render_bindings()`, `rzig_status()`); the export scan and
the generated bindings are pure R, so the examples and the tests run without a
Zig compiler and the vignette executes its generation steps; Zig support is
limited to the 0.16 and 0.17 release series; the generated `entry.c` no longer includes
`R_ext/Visibility.h`, which some R installations do not ship; the license is
GPL-3.

## Test environments

* local: macOS 26 (arm64), R 4.6.1, with and without Zig on the PATH
* GitHub Actions: Ubuntu (R release and R-devel), macOS (R release),
  Windows (R release); Debian testing and Ubuntu with the distribution R
  packages; Fedora; rocker/r-ver:4.6.1
* Zig 0.16.0 and 0.17.0 where client packages were compiled

## R CMD check results

0 errors | 0 warnings | 0 notes

## Notes

The package itself contains no compiled code. The Zig compiler named in
SystemRequirements is needed only to install packages created with the
scaffold, as the examples and the documentation state.
