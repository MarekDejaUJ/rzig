test_that("test_zig needs a tests.zig file", {
  path <- local_package("notests")
  suppressMessages(use_rzig(path))
  expect_error(test_zig(path), "create src/rzig/src/tests.zig", fixed = TRUE)
})

test_that("test_zig runs the Zig tests of a package and names failures", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  path <- local_package("zigtests")
  suppressMessages(use_rzig(path))
  src <- file.path(path, "src", "rzig", "src")
  writeLines(c("pub fn double(x: f64) f64 {", "    return 2 * x;", "}",
    'const std = @import("std");', 'test "double doubles" {',
    "    try std.testing.expectEqual(@as(f64, 6), double(3));", "}"), file.path(src, "kernels.zig"))
  writeLines(c("test {", '    _ = @import("kernels.zig");', "}"), file.path(src, "tests.zig"))
  result <- test_zig(path)
  expect_true(result$ok)
  expect_output(print(result), "Zig tests passed")
  expect_false(dir.exists(file.path(path, "src", "rzig", ".zig-cache")))
  writeLines(c('const std = @import("std");', 'test "a wrong expectation" {',
    "    try std.testing.expectEqual(@as(i32, 5), 2 + 2);", "}"), file.path(src, "tests.zig"))
  expect_warning(result <- test_zig(path), "failed")
  expect_false(result$ok)
  expect_true(any(grepl("a wrong expectation", result$failed, fixed = TRUE)))
})
