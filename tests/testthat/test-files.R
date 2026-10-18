multi_package <- function(name, env = parent.frame()) {
  path <- local_package(name, env = env)
  suppressMessages(use_rzig(path))
  src <- file.path(path, "src", "rzig", "src")
  text <- readLines(file.path(src, "main.zig"))
  imports <- c('pub const stats = @import("stats.zig");', 'const helpers = @import("helpers.zig");',
    "/// Three times a value, re-exported from helpers.zig.", "/// @export",
    "pub const triple = helpers.triple;", "")
  writeLines(append(text, imports, after = grep("^const rzig", text)), file.path(src, "main.zig"))
  writeLines(c("/// Twice a value.", "/// @param x A number.", "/// @export",
    "pub fn twice(x: f64) f64 {", "    return 2 * x;", "}", "",
    'pub const nested = @import("nested/inner.zig");'), file.path(src, "stats.zig"))
  dir.create(file.path(src, "nested"))
  writeLines(c("/// Square a value.", "/// @export internal", "pub fn square(x: f64) f64 {",
    "    return x * x;", "}"), file.path(src, "nested", "inner.zig"))
  writeLines(c("pub fn triple(x: f64) f64 {", "    return 3 * x;", "}"), file.path(src, "helpers.zig"))
  path
}

test_that("exports are found in files that main.zig imports publicly", {
  path <- multi_package("multipkg")
  exports <- scan_exports(path)
  names <- vapply(exports, function(item) item$name, character(1L))
  expect_setequal(names, c("hello_zig", "twice", "square", "triple"))
  identifier <- function(name) exports[[which(names == name)]]$identifier
  expect_identical(identifier("twice"), "stats.twice")
  expect_identical(identifier("square"), "stats.nested.square")
  expect_identical(identifier("triple"), "triple")
  expect_true(exports[[which(names == "square")]]$internal)
  expect_identical(exports[[which(names == "square")]]$file, "nested/inner.zig")
  expect_identical(exports[[which(names == "triple")]]$parameters, "x")
  expect_setequal(attr(exports, "files"), c("main.zig", "stats.zig", "nested/inner.zig", "helpers.zig"))
  bindings <- render_bindings(exports)
  expect_match(bindings$manifest, ".func = bound_root.stats.nested.square,", fixed = TRUE)
  expect_match(bindings$manifest, ".func = bound_root.triple,", fixed = TRUE)
  expect_output(print(exports), "[stats.zig]", fixed = TRUE)
  suppressMessages(document(path))
  expect_true(rzig_status(path)$ok[rzig_status(path)$step == "Bindings"])
})

test_that("markers in files the registration cannot reach are reported", {
  path <- local_package("privatepkg")
  suppressMessages(use_rzig(path))
  src <- file.path(path, "src", "rzig", "src")
  text <- readLines(file.path(src, "main.zig"))
  writeLines(append(text, 'const other = @import("other.zig");', after = grep("^const rzig", text)),
    file.path(src, "main.zig"))
  writeLines(c("/// @export", "pub fn hidden(x: f64) f64 {", "    return x;", "}"), file.path(src, "other.zig"))
  expect_error(scan_exports(path), "write `pub const other = @import(\"other.zig\");`", fixed = TRUE)
  status <- rzig_status(path)
  expect_false(status$ok[status$step == "Exports"])
  writeLines(text, file.path(src, "main.zig"))
  status <- rzig_status(path)
  expect_true(status$ok[status$step == "Exports"])
  expect_match(status$detail[status$step == "Exports"], "other.zig contains `/// @export`", fixed = TRUE)
  writeLines(c(text[seq_len(grep("^const rzig", text))], 'pub const other = @import("other.zig");',
    "/// @export", "pub fn hidden(x: f64) f64 {", "    return x;", "}",
    text[-seq_len(grep("^const rzig", text))]), file.path(src, "main.zig"))
  expect_error(scan_exports(path), "`hidden` is exported more than once", fixed = TRUE)
})

test_that("a package with exports in several files builds and runs", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  path <- multi_package("multibuild")
  writeLines(c(
    "Package: multibuild", "Version: 0.0.1", "Title: Several Zig Files", "License: GPL-3",
    "Description: Exports from several Zig files.",
    "Authors@R: person('A', 'B', email = 'a@example.org', role = c('aut', 'cre'))"
  ), file.path(path, "DESCRIPTION"))
  suppressMessages(document(path))
  result <- build_zig(path)
  expect_true(result$ok)
  output <- run_r(paste(
    sprintf("library(multibuild, lib.loc = '%s')", result$library),
    "stopifnot(twice(4) == 8, triple(2) == 6, multibuild:::square(3) == 9, !exists('square'))",
    "cat('files ok')", sep = "; "))
  expect_null(attr(output, "status"))
  expect_match(as.character(output), "files ok", fixed = TRUE)
})
