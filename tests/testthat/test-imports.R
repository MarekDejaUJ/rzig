zig_module_header <- c(
  "const rzig = @import(\"rzig\");",
  "const kernels = @import(\"kernels\");",
  "",
  "pub const panic = rzig.Panic;",
  "",
  "comptime {",
  "    rzig.registerModule(@This());",
  "}",
  ""
)

test_that("use_rzig_import() and use_rzig_module() edit DESCRIPTION", {
  provider <- local_package("kernelfield")
  suppressMessages(use_rzig_module(provider, "kernels"))
  expect_true(file.exists(file.path(provider, "inst", "zig", "kernels", "root.zig")))
  expect_true(file.exists(file.path(provider, "inst", "include", "kernelfield_rzig.h")))
  fields <- read.dcf(file.path(provider, "DESCRIPTION"))
  expect_identical(unname(fields[1L, "Config/rzig/imports"]), "kernelfield/kernels")
  expect_false("LinkingTo" %in% colnames(fields))
  consumer <- local_package("userfield")
  cat("LinkingTo: Rcpp (>= 1.0.0)\n", file = file.path(consumer, "DESCRIPTION"), append = TRUE)
  suppressMessages(use_rzig_import(consumer, "kernelfield", "kernels"))
  suppressMessages(use_rzig_import(consumer, "kernelfield", "kernels"))
  fields <- read.dcf(file.path(consumer, "DESCRIPTION"))
  expect_identical(unname(fields[1L, "Config/rzig/imports"]), "kernelfield/kernels")
  expect_identical(unname(fields[1L, "LinkingTo"]), "Rcpp (>= 1.0.0), kernelfield")
  expect_error(use_rzig_import(consumer, "kernelfield", "std"), "reserved")
  expect_error(use_rzig_import(consumer, "kernelfield", "1bad"), "Zig identifier")
  expect_error(use_rzig_module(provider, "rzig"), "reserved")
})

test_that("the imports resolve to installed modules and checks name the problems", {
  tool <- rzig:::.rzig_imports_tool()
  provider <- local_package("kernelsrc")
  suppressMessages(use_rzig_module(provider, "kernels"))
  resolved <- tool$rzig_imports_resolve(provider)
  expect_identical(names(resolved), "kernels")
  expect_true(endsWith(resolved[["kernels"]], "inst/zig/kernels/root.zig"))
  consumer <- local_package("usersrc")
  suppressMessages(use_rzig(consumer))
  suppressMessages(use_rzig_import(consumer, "notinstalledpkg", "kernels"))
  expect_error(tool$rzig_imports_resolve(consumer), "package notinstalledpkg is not installed")
  problems <- rzig:::.rzig_check_description(consumer)$problems
  expect_true(any(grepl("notinstalledpkg is not installed", problems, fixed = TRUE)))
  lines <- readLines(file.path(consumer, "DESCRIPTION"))
  writeLines(lines[!startsWith(lines, "LinkingTo:")], file.path(consumer, "DESCRIPTION"))
  problems <- rzig:::.rzig_check_description(consumer)$problems
  expect_true(any(grepl("which LinkingTo does not list", problems, fixed = TRUE)))
  writeLines(c("Package: twice", "Config/rzig/imports: a/kernels, b/kernels"), file.path(consumer, "DESCRIPTION"))
  expect_error(tool$rzig_imports_resolve(consumer), "names the module 'kernels' twice")
})

test_that("a package imports a Zig module of another package", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  root <- local_tempdir()
  lib <- file.path(root, "lib")
  dir.create(lib)
  provider <- file.path(root, "kernelpkg")
  suppressMessages(create_rzig_package(provider, tests = FALSE))
  suppressMessages(use_rzig_module(provider, "kernels"))
  writeLines(c(zig_module_header,
    "/// The sum of the values, by the package's own module.",
    "/// @export",
    "pub fn kernel_sum(x: []const f64) f64 {",
    "    return kernels.sum(x);",
    "}"
  ), file.path(provider, "src", "rzig", "src", "main.zig"))
  suppressMessages(document(provider))
  built <- suppressWarnings(build_zig(provider, lib = lib))
  expect_true(built$ok, info = paste(built$log, collapse = "\n"))

  consumer <- file.path(root, "userpkg")
  suppressMessages(create_rzig_package(consumer, tests = FALSE))
  suppressMessages(use_rzig_import(consumer, "kernelpkg", "kernels"))
  writeLines(c(zig_module_header,
    "/// Twice the sum of the values, by the module of kernelpkg.",
    "/// @export",
    "pub fn user_total(x: []const f64) f64 {",
    "    return 2 * kernels.sum(x);",
    "}"
  ), file.path(consumer, "src", "rzig", "src", "main.zig"))
  writeLines(c("const std = @import(\"std\");", "const kernels = @import(\"kernels\");",
    "test \"the module of kernelpkg\" {", "    try std.testing.expectEqual(@as(f64, 3), kernels.sum(&.{ 1, 2 }));", "}"),
    file.path(consumer, "src", "rzig", "src", "tests.zig"))
  suppressMessages(document(consumer))
  old_paths <- .libPaths()
  .libPaths(c(lib, old_paths))
  on.exit(.libPaths(old_paths), add = TRUE)
  expect_length(rzig:::.rzig_check_description(consumer)$problems, 0L)
  tests <- suppressWarnings(test_zig(consumer))
  expect_true(tests$ok, info = paste(tests$log, collapse = "\n"))
  built <- suppressWarnings(build_zig(consumer, lib = lib))
  expect_true(built$ok, info = paste(built$log, collapse = "\n"))
  output <- run_r(paste(
    sprintf(".libPaths(c(%s, .libPaths()))", deparse(lib)),
    "cat('own', kernelpkg::kernel_sum(c(1, 2, 3)), '\\n')",
    "cat('imported', userpkg::user_total(c(1, 2, 3)), '\\n')",
    sep = "\n"
  ))
  expect_match(output, "own 6", fixed = TRUE)
  expect_match(output, "imported 12", fixed = TRUE)
})
