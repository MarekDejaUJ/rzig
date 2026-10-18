test_that("build_zig accepts only the optimize modes with safety checks", {
  path <- local_package("optmodes")
  suppressMessages(use_rzig(path))
  expect_error(build_zig(path, optimize = "ReleaseFast"), "ReleaseSafe", fixed = TRUE)
  expect_error(build_zig(path, optimize = c("Debug", "ReleaseSafe")), "must be")
  old <- Sys.getenv("RZIG_OPTIMIZE", unset = NA)
  Sys.setenv(RZIG_OPTIMIZE = "ReleaseSmall")
  on.exit(if (is.na(old)) Sys.unsetenv("RZIG_OPTIMIZE") else Sys.setenv(RZIG_OPTIMIZE = old), add = TRUE)
  expect_error(build_zig(path), "got \"ReleaseSmall\"", fixed = TRUE)
})

test_that("Debug builds keep Zig's safety checks", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  path <- local_package("optdebug")
  suppressMessages(use_rzig(path))
  writeLines(c(
    'const std = @import("std");', 'const builtin = @import("builtin");', 'const rzig = @import("rzig");',
    "pub const panic = if (builtin.is_test)", "    std.debug.FullPanic(std.debug.defaultPanic)",
    "else", "    rzig.Panic;",
    "/// @export", "pub fn build_mode() []const u8 {", "    return @tagName(builtin.mode);", "}",
    "/// @export", "pub fn element(x: []const f64, i: usize) f64 {", "    return x[i];", "}",
    "comptime {", "    rzig.registerModule(@This());", "}"
  ), file.path(path, "src", "rzig", "src", "main.zig"))
  suppressMessages(document(path))
  lib <- local_tempdir()
  result <- build_zig(path, lib = lib, optimize = "Debug")
  expect_true(result$ok)
  expect_identical(result$optimize, "Debug")
  expect_output(print(result), "Optimize mode: Debug", fixed = TRUE)
  output <- run_r(sprintf(paste0(
    ".libPaths(c(%s, .libPaths())); library(optdebug); cat(build_mode(), '\\n'); ",
    "cat(tryCatch(element(c(1, 2), 5L), error = function(e) 'R error'), '\\n')"
  ), deparse(lib)))
  expect_match(output, "^(Debug|debug)", perl = TRUE)
  if (!identical(.Platform$OS.type, "windows")) expect_match(output, "R error", fixed = TRUE)
  release <- build_zig(path, lib = lib, optimize = "ReleaseSafe")
  expect_true(release$ok)
  output <- run_r(sprintf(".libPaths(c(%s, .libPaths())); library(optdebug); cat(build_mode(), '\\n')",
    deparse(lib)))
  expect_match(output, "^(ReleaseSafe|safe)", perl = TRUE)
})

test_that("the generated Makevars reject optimize modes without safety checks", {
  skip_on_cran()
  skip_on_os("windows")
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  path <- local_package("optreject")
  suppressMessages(use_rzig(path))
  lib <- local_tempdir()
  log <- suppressWarnings(system2(file.path(R.home("bin"), "R"),
    c("CMD", "INSTALL", paste0("--library=", shQuote(lib)), shQuote(path)),
    stdout = TRUE, stderr = TRUE,
    env = c("RZIG_OPTIMIZE=ReleaseFast", paste0("ZIG=", find_zig()$path))))
  expect_false(is.null(attr(log, "status")))
  expect_true(any(grepl("RZIG_OPTIMIZE must be ReleaseSafe or Debug; got ReleaseFast", log, fixed = TRUE)))
})
