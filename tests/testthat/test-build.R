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

test_that("duplicate symbols are reported at the link step", {
  log <- c(
    "* installing *source* package 'dup' ...",
    "duplicate symbol '_R_init_dup' in:",
    "    dup/src/entry.o",
    "    dup/src/extra.o",
    "ld: 1 duplicate symbols",
    "clang: error: linker command failed with exit code 1 (use -v to see invocation)",
    "ERROR: compilation failed for package 'dup'"
  )
  parsed <- rzig:::.rzig_parse_build_log(log, "dup")
  expect_identical(parsed$step, "link")
  expect_match(parsed$errors$message[[1L]], "duplicate symbol", fixed = TRUE)
  gnu <- c("/usr/bin/ld: extra.o: in function `R_init_dup':",
    "extra.c:(.text+0x0): multiple definition of `R_init_dup'; entry.o:entry.c:(.text+0x0): first defined here",
    "collect2: error: ld returned 1 exit status")
  expect_identical(rzig:::.rzig_parse_build_log(gnu, "dup")$step, "link")
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

test_that("exports named like C library functions do not replace them", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  path <- local_package("clashpkg")
  writeLines(c(
    "Package: clashpkg", "Version: 0.0.1", "Title: Symbol Names", "License: GPL-3",
    "Description: Exports named like C library functions.",
    "Authors@R: person('A', 'B', email = 'a@example.org', role = c('aut', 'cre'))"
  ), file.path(path, "DESCRIPTION"))
  use_rzig(path)
  main <- file.path(path, "src", "rzig", "src", "main.zig")
  text <- readLines(main)
  exports <- c(
    "/// @export", "pub fn exp(x: f64) f64 {", "    return @exp(x);", "}",
    "/// @export", "pub fn log(x: f64) f64 {", "    return @log(x);", "}",
    "/// @export", "pub fn sqrt(x: f64) f64 {", "    return @sqrt(x);", "}",
    "/// @export", "pub fn free(x: f64) f64 {", "    return x;", "}",
    "/// @export", "pub fn malloc(x: f64) f64 {", "    return x + 1;", "}",
    "/// @export", "pub fn memcpy(x: f64) f64 {", "    return x + 2;", "}", ""
  )
  writeLines(append(text, exports, after = grep("^comptime", text) - 1L), main)
  document(path)
  status <- rzig_status(path)
  expect_match(status$detail[status$step == "Exports"], "`log` masks base::log", fixed = TRUE)
  result <- build_zig(path)
  expect_true(result$ok)
  script <- paste(
    sprintf("library(clashpkg, lib.loc = %s, warn.conflicts = FALSE)", deparse(result$library)),
    "stopifnot(all.equal(clashpkg::exp(1), base::exp(1)), all.equal(clashpkg::log(2), base::log(2)))",
    "stopifnot(clashpkg::sqrt(4) == 2, clashpkg::free(3) == 3, clashpkg::malloc(1) == 2)",
    "stopifnot(clashpkg::memcpy(1) == 3, identical(hello_zig('R'), 'Hello, R!'))",
    "cat('calls ok')",
    sep = "; "
  )
  output <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"), c("--vanilla", "-e", shQuote(script)),
    stdout = TRUE, stderr = TRUE
  ))
  expect_null(attr(output, "status"))
  expect_match(paste(output, collapse = "\n"), "calls ok", fixed = TRUE)
  nm <- Sys.which("nm")
  skip_if(!nzchar(nm) || .Platform$OS.type == "windows", "no nm on this platform")
  library_file <- list.files(file.path(result$library, "clashpkg", "libs"),
    pattern = "\\.(so|dylib)$", full.names = TRUE)
  arguments <- if (identical(Sys.info()[["sysname"]], "Darwin")) "-gU" else c("-D", "--defined-only")
  symbols <- system2(nm, c(arguments, shQuote(library_file)), stdout = TRUE)
  defined <- sub("^_", "", sub("^.*[[:space:]]", "", symbols))
  expect_false(any(c("exp", "log", "sqrt", "free", "malloc", "memcpy", "rzig_init") %in% defined))
  expect_true("R_init_clashpkg" %in% defined)
})

inplace_package <- function(name) {
  path <- local_package(name, env = parent.frame())
  writeLines(c(
    paste("Package:", name), "Version: 0.0.1", "Title: In-Place Builds", "License: GPL-3",
    "Description: Rebuilds after edits of helper Zig files.",
    "Authors@R: person('A', 'B', email = 'a@example.org', role = c('aut', 'cre'))"
  ), file.path(path, "DESCRIPTION"))
  use_rzig(path)
  writeLines(c(
    'const std = @import("std");', 'const builtin = @import("builtin");', 'const rzig = @import("rzig");',
    'const helper = @import("helper.zig");',
    'pub const panic = if (builtin.is_test) std.debug.FullPanic(std.debug.defaultPanic) else rzig.Panic;',
    "/// Return the helper constant.", "/// @export", "pub fn value() f64 {",
    "    return helper.constant();", "}", "comptime {", "    rzig.registerModule(@This());", "}"
  ), file.path(path, "src", "rzig", "src", "main.zig"))
  set_constant(path, "1.0")
  document(path)
  path
}

set_constant <- function(path, value) {
  writeLines(c("pub fn constant() f64 {", paste0("    return ", value, ";"), "}"),
    file.path(path, "src", "rzig", "src", "helper.zig"))
}

test_that("an in-place installation rebuilds after an edit of a helper Zig file", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  path <- inplace_package("inplacepkg")
  lib <- tempfile("rzig-inplace-lib-")
  dir.create(lib)
  on.exit(unlink(lib, recursive = TRUE), add = TRUE)
  install <- function() {
    out <- suppressWarnings(system2(file.path(R.home("bin"), "R"),
      c("CMD", "INSTALL", "--no-multiarch", paste0("--library=", shQuote(lib)), shQuote(path)),
      stdout = TRUE, stderr = TRUE, env = paste0("ZIG=", find_zig()$path)))
    expect_null(attr(out, "status"))
  }
  value <- function() run_r(sprintf("library(inplacepkg, lib.loc = %s); cat(value())", deparse(lib)))
  install()
  expect_identical(as.character(value()), "1")
  set_constant(path, "2.0")
  install()
  expect_identical(as.character(value()), "2")
})

test_that("devtools::load_all() recompiles after an edit of a helper Zig file", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  skip_if_not_installed("pkgload")
  skip_if_not_installed("pkgbuild")
  path <- inplace_package("loadallpkg")
  # deparse() escapes the backslashes of Windows paths inside the R code.
  code <- sprintf(paste(
    "Sys.setenv(ZIG = %s)",
    "pkgload::load_all(%s, quiet = TRUE); a <- value()",
    "writeLines(c('pub fn constant() f64 {', '    return 3.0;', '}'), file.path(%s, 'src', 'rzig', 'src', 'helper.zig'))",
    "pkgload::load_all(%s, quiet = TRUE); b <- value()",
    "cat(a, b)", sep = "; "), deparse(find_zig()$path), deparse(path), deparse(path), deparse(path))
  result <- run_r(code)
  expect_null(attr(result, "status"))
  expect_match(as.character(result), "1 3", fixed = TRUE)
})

test_that("printing a build warns about a package loaded in the session", {
  result <- structure(list(
    ok = TRUE, package = "stats", seconds = 1, library = tempdir(),
    zig = list(path = "zig", version = "0.16.0")
  ), class = "rzig_build")
  expect_output(print(result), "already loaded in this session")
})

test_that("an internal routine is callable from the package but not exported", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  path <- local_package("internalpkg")
  writeLines(c(
    "Package: internalpkg", "Version: 0.0.1", "Title: Internal Routines", "License: GPL-3",
    "Description: Calls an internal Zig routine from R.",
    "Authors@R: person('A', 'B', email = 'a@example.org', role = c('aut', 'cre'))"
  ), file.path(path, "DESCRIPTION"))
  use_rzig(path)
  main <- file.path(path, "src", "rzig", "src", "main.zig")
  text <- readLines(main)
  routine <- c("/// Double a value for the package's R code.", "/// @export internal",
    "pub fn twice_internal(x: f64) f64 {", "    return 2 * x;", "}", "")
  writeLines(append(text, routine, after = grep("^comptime", text) - 1L), main)
  writeLines(c("#' Quadruple a value", "#' @param x A number.", "#' @export",
    "quadruple <- function(x) twice_internal(twice_internal(x))"), file.path(path, "R", "quadruple.R"))
  cat("export(quadruple)\n", file = file.path(path, "NAMESPACE"), append = TRUE)
  document(path)
  expect_true(rzig_status(path)$ok[rzig_status(path)$step == "Bindings"])
  result <- build_zig(path)
  expect_true(result$ok)
  output <- run_r(paste(
    sprintf("library(internalpkg, lib.loc = %s)", deparse(result$library)),
    "stopifnot(quadruple(2) == 8, !exists('twice_internal'), internalpkg:::twice_internal(3) == 6)",
    "stopifnot(.Call(internalpkg:::twice_internal_, 5) == 10, !'twice_internal' %in% getNamespaceExports('internalpkg'))",
    "cat('internal ok')", sep = "; "))
  expect_null(attr(output, "status"))
  expect_match(as.character(output), "internal ok", fixed = TRUE)
})

test_that("a package works when roxygen2 regenerated its NAMESPACE last", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  skip_if_not_installed("roxygen2")
  path <- local_package("roxbuild")
  writeLines(c(
    "Package: roxbuild", "Version: 0.0.1", "Title: Roxygen Build", "License: GPL-3",
    "Description: Builds after roxygen2.", "Encoding: UTF-8",
    "Authors@R: person('A', 'B', email = 'a@example.org', role = c('aut', 'cre'))"
  ), file.path(path, "DESCRIPTION"))
  writeLines("# Generated by roxygen2: do not edit by hand", file.path(path, "NAMESPACE"))
  use_rzig(path)
  roxygen2::roxygenise(path, load_code = roxygen2::load_source)
  result <- build_zig(path)
  expect_true(result$ok)
  output <- run_r(paste(
    sprintf("library(roxbuild, lib.loc = %s)", deparse(result$library)),
    "stopifnot(identical(hello_zig('roxygen'), 'Hello, roxygen!'))", "cat('roxygen ok')", sep = "; "))
  expect_null(attr(output, "status"))
  expect_match(as.character(output), "roxygen ok", fixed = TRUE)
})

test_that("a fresh scaffold passes R CMD check", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  path <- local_package("checkpkg")
  writeLines(c(
    "Package: checkpkg", "Version: 0.0.1", "Title: A Checked Scaffold", "License: GPL-3",
    "Description: Checks the scaffold of 'rzig' with R CMD check.", "Encoding: UTF-8",
    "Authors@R: person('A', 'B', email = 'a@example.org', role = c('aut', 'cre'))",
    "SystemRequirements: Zig 0.16.x or 0.17.x"
  ), file.path(path, "DESCRIPTION"))
  use_rzig(path)
  work <- tempfile("rzig-check-")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  r <- file.path(R.home("bin"), "R")
  old <- setwd(work)
  on.exit(setwd(old), add = TRUE)
  build <- suppressWarnings(system2(r, c("CMD", "build", shQuote(path)), stdout = TRUE, stderr = TRUE))
  expect_null(attr(build, "status"))
  tarball <- list.files(work, pattern = "^checkpkg_.*\\.tar\\.gz$")
  check <- suppressWarnings(system2(r, c("CMD", "check", "--no-manual", tarball),
    stdout = TRUE, stderr = TRUE, env = c(paste0("ZIG=", find_zig()$path), "_R_CHECK_FORCE_SUGGESTS_=false")))
  log <- readLines(file.path(work, "checkpkg.Rcheck", "00check.log"))
  status <- grep("^Status:", log, value = TRUE)
  expect_false(any(grepl("ERROR|WARNING", status)), info = paste(log, collapse = "\n"))
  expect_true(any(grepl("checking examples ... OK", log, fixed = TRUE)))
})

test_that("RZIG_ZIG_CACHE keeps the Zig cache outside the package", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  path <- local_package("cachepkg")
  writeLines(c(
    "Package: cachepkg", "Version: 0.0.1", "Title: Cache Test", "License: GPL-3",
    "Description: Uses a persistent Zig cache.",
    "Authors@R: person('A', 'B', email = 'a@example.org', role = c('aut', 'cre'))"
  ), file.path(path, "DESCRIPTION"))
  use_rzig(path)
  cache <- tempfile("rzig-zig-cache-")
  old <- Sys.getenv("RZIG_ZIG_CACHE", unset = NA)
  Sys.setenv(RZIG_ZIG_CACHE = cache)
  on.exit({
    if (is.na(old)) Sys.unsetenv("RZIG_ZIG_CACHE") else Sys.setenv(RZIG_ZIG_CACHE = old)
    unlink(cache, recursive = TRUE)
  }, add = TRUE)
  first <- build_zig(path)
  expect_true(first$ok)
  expect_true(length(list.files(cache, recursive = TRUE)) > 0L)
  second <- build_zig(path)
  expect_true(second$ok)
})

test_that("renamed, invisible and defaulted exports work after a build", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  env <- new.env()
  zig_function(c(
    "/// @default y 2", "/// @export name=add_default", "pub fn add_zig(x: f64, y: f64) f64 {", "    return x + y;", "}",
    "/// @export invisible", "pub fn quiet_value(x: f64) f64 {", "    return x;", "}"
  ), env = env)
  expect_identical(env$add_default(1), 3)
  expect_identical(env$add_default(1, 5), 6)
  visible <- withVisible(env$quiet_value(4))
  expect_false(visible$visible)
  expect_identical(visible$value, 4)
})
