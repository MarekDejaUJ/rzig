# Run the Zig tests of a package

Runs `zig build test` for the client package: the `test` blocks reached
from `src/rzig/src/tests.zig` are compiled for the host and run without
R. `tests.zig` imports the files whose tests should run, for example
`test { _ = @import("kernels.zig"); }`; files that use the `rzig` module
need R and cannot run there, so numerical kernels are best kept in files
of plain Zig. The package folder receives no build output.

## Usage

``` r
test_zig(path)
```

## Arguments

- path:

  Path to a package previously initialized with
  [`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md).

## Value

An object of class `rzig_zig_tests`: a list with `ok`, `failed` (the
names of failed tests), `seconds` and `log`, invisibly. A failure also
signals a warning.

## Examples

``` r
# \donttest{
if (isTRUE(find_zig(required = FALSE)$supported)) {
  package_path <- tempfile("rzig-tests-", tmpdir = tempdir())
  dir.create(package_path)
  writeLines(c("Package: examplepkg", "Version: 0.0.1"),
    file.path(package_path, "DESCRIPTION"))
  use_rzig(package_path)
  writeLines(c("const std = @import(\"std\");", "test \"addition\" {",
    "    try std.testing.expectEqual(4, 2 + 2);", "}"),
    file.path(package_path, "src", "rzig", "src", "tests.zig"))
  test_zig(package_path)
  unlink(package_path, recursive = TRUE)
}
#> Generated RZig bindings for examplepkg: 1 exported function
#> Created RZig scaffold for package examplepkg
# }
```
