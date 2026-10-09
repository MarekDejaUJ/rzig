read_log <- function(name) readLines(fixture_path("logs", paste0(name, ".log")), warn = FALSE)

test_that("an unsupported Zig type is reported with its function", {
  parsed <- rzig:::.rzig_parse_build_log(read_log("badtype"), "badtype", "/tmp/rzig-library")
  expect_identical(parsed$step, "compile")
  expect_identical(nrow(parsed$errors), 1L)
  expect_identical(parsed$errors$file, "src/rzig/framework/convert.zig")
  expect_identical(parsed$errors$line, 138L)
  expect_match(parsed$errors$message, "function `total`, parameter 1 has unsupported type", fixed = TRUE)
  expect_match(parsed$errors$message, "nearest supported alternative: []const f64", fixed = TRUE)
})

test_that("a C compiler error is reported with its file in src", {
  parsed <- rzig:::.rzig_parse_build_log(read_log("badc"), "badc")
  expect_identical(parsed$step, "compile")
  expect_identical(parsed$errors$file, "src/entry.c")
  expect_identical(parsed$errors$line, 1L)
  expect_match(parsed$errors$message, "NoSuchHeader.h' file not found", fixed = TRUE)
})

test_that("a rejected Zig version is reported from configure", {
  parsed <- rzig:::.rzig_parse_build_log(read_log("badversion"), "badversion")
  expect_identical(parsed$step, "configure")
  expect_match(parsed$errors$message, "Zig 0.15.2 found", fixed = TRUE)
  expect_match(parsed$errors$message, "requires Zig 0.16.x or 0.17.x", fixed = TRUE)
})

test_that("a missing registration block is reported at the load step", {
  parsed <- rzig:::.rzig_parse_build_log(read_log("noregister"), "noregister", "/tmp/rzig-library")
  expect_identical(parsed$step, "load")
  expect_match(parsed$errors$message, "<library>/00LOCK-noregister", fixed = TRUE)
  expect_match(parsed$errors$message, "rzig.registerModule(@This())", fixed = TRUE)
})

test_that("a Zig syntax error is located in main.zig", {
  parsed <- rzig:::.rzig_parse_build_log(read_log("badsyntax"), "badsyntax")
  expect_identical(parsed$step, "compile")
  expect_identical(parsed$errors$file, "src/rzig/src/main.zig")
  expect_identical(parsed$errors$line, 18L)
  expect_identical(parsed$errors$column, 16L)
})

test_that("compiler paths map to package paths", {
  map <- rzig:::.rzig_package_file
  expect_identical(map("framework/boundary.zig", "p"), "src/rzig/framework/boundary.zig")
  expect_identical(map("src/main.zig", "p"), "src/rzig/src/main.zig")
  expect_identical(map("entry.c", "p"), "src/entry.c")
  expect_identical(map("/tmp/x/p/src/entry.c", "p"), "src/entry.c")
  expect_identical(map("C:\\tmp\\p\\src\\rzig\\src\\main.zig", "p"), "src/rzig/src/main.zig")
})

test_that("build_zig stops before compiling when a check fails", {
  path <- local_package("stalepkg")
  use_rzig(path)
  main <- file.path(path, "src", "rzig", "src", "main.zig")
  cat("/// @export\npub fn twice(x: f64) f64 {\n    return 2 * x;\n}\n", file = main, append = TRUE)
  expect_warning(result <- build_zig(path), "preflight")
  expect_s3_class(result, "rzig_build")
  expect_false(result$ok)
  expect_identical(result$step, "preflight")
  expect_true(any(grepl("^Bindings: out of date", result$problems)))
  expect_output(print(result), "not started")
})

test_that("build_zig compiles and installs a package", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  path <- local_package("buildok")
  writeLines(c(
    "Package: buildok", "Version: 0.0.1", "Title: Build Test", "License: GPL-3",
    "Description: Tests build_zig().",
    "Authors@R: person('A', 'B', email = 'a@example.org', role = c('aut', 'cre'))"
  ), file.path(path, "DESCRIPTION"))
  use_rzig(path)
  result <- build_zig(path)
  expect_true(result$ok)
  expect_true(dir.exists(file.path(result$library, "buildok")))
  expect_false(any(grepl("\\.o$", list.files(file.path(path, "src"), recursive = TRUE))))
  expect_output(print(result), "succeeded")
})

test_that("build_zig reports the compiler error of an unsupported type", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  path <- local_package("buildbad")
  use_rzig(path)
  main <- file.path(path, "src", "rzig", "src", "main.zig")
  text <- readLines(main)
  text <- append(text, c("/// @export", "pub fn total(x: []const f32) f64 {",
    "    return @floatCast(x[0]);", "}", ""), after = grep("^comptime", text) - 1L)
  writeLines(text, main)
  document(path)
  expect_warning(result <- build_zig(path, preflight = FALSE), "compile")
  expect_identical(result$step, "compile")
  expect_identical(result$errors$function_name[[1L]], "total")
  expect_output(print(result), "unsupported type")
})

test_that("printing a build warns about a package loaded in the session", {
  result <- structure(list(
    ok = TRUE, package = "stats", seconds = 1, library = tempdir(),
    zig = list(path = "zig", version = "0.16.0")
  ), class = "rzig_build")
  expect_output(print(result), "already loaded in this session")
})
