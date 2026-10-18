# These tests replace the downloader of a test package by a script that
# records its arguments and links the Zig compiler of this machine, so they
# exercise the configure logic without network access.

without_zig_path <- function() {
  path <- strsplit(Sys.getenv("PATH"), .Platform$path.sep, fixed = TRUE)[[1L]]
  paste(path[!file.exists(file.path(path, "zig"))], collapse = .Platform$path.sep)
}

install_log <- function(package, lib, env) {
  log <- suppressWarnings(system2(file.path(R.home("bin"), "R"),
    c("CMD", "INSTALL", paste0("--library=", shQuote(lib)), shQuote(package)),
    stdout = TRUE, stderr = TRUE, env = env))
  structure(as.character(log), status = attr(log, "status"))
}

# The compiler configure reports, as its version, folder and installation.
expect_used_zig <- function(log, version, home, folder) {
  used <- sub("^using Zig ([^ ]+) at ", "", grep("^using Zig ", log, value = TRUE))
  expect_length(used, 1L)
  expect_true(any(grepl(paste0("^using Zig ", version, " at "), log)))
  expect_identical(basename(used), "zig")
  expect_identical(basename(dirname(used)), folder)
  expect_identical(normalizePath(dirname(dirname(used))), home)
}

stub_fetch <- function(package, zig, record, fail = FALSE) {
  writeLines(c(
    "arguments <- commandArgs(trailingOnly = TRUE)",
    sprintf("writeLines(arguments, %s)", deparse(record)),
    if (fail) "quit(save = 'no', status = 1L)",
    "target <- file.path(arguments[[2L]], paste0('zig-stub-', arguments[[1L]]))",
    "dir.create(arguments[[2L]], recursive = TRUE, showWarnings = FALSE)",
    sprintf("invisible(if (!file.exists(target)) file.symlink(%s, target))", deparse(dirname(zig))),
    "cat(file.path(target, 'zig'), '\\n', sep = '')"
  ), file.path(package, "src", "rzig", "tools", "fetch_zig.R"))
}

test_that("configure downloads Zig only when RZIG_DOWNLOAD_ZIG asks for it", {
  skip_on_cran()
  skip_on_os("windows")
  compiler <- find_zig(required = FALSE)
  skip_if_not(isTRUE(compiler$supported), "no supported Zig compiler")
  zig <- normalizePath(compiler$path)
  package <- local_package("zigdownload")
  suppressMessages(use_rzig(package))
  record <- file.path(local_tempdir(), "arguments")
  stub_fetch(package, zig, record)
  cache <- local_tempdir()
  base_env <- c(paste0("PATH=", shQuote(without_zig_path())), paste0("HOME=", shQuote(local_tempdir())),
    paste0("R_USER_CACHE_DIR=", shQuote(cache)), "ZIG=", "RZIG_ZIG_HOME=")

  log <- install_log(package, local_tempdir(), c(base_env, "RZIG_DOWNLOAD_ZIG="))
  expect_false(is.null(attr(log, "status")))
  expect_true(any(grepl("With RZIG_DOWNLOAD_ZIG=true, the", log, fixed = TRUE)))
  expect_false(file.exists(record))

  lib <- local_tempdir()
  log <- install_log(package, lib, c(base_env, "RZIG_DOWNLOAD_ZIG=true"))
  expect_null(attr(log, "status"))
  home <- normalizePath(file.path(cache, "R", "rzig", "zig"))
  arguments <- readLines(record)
  expect_identical(arguments[[1L]], "0.16.0")
  expect_identical(normalizePath(arguments[[2L]]), home)
  expect_used_zig(log, compiler$version, home, "zig-stub-0.16.0")
  expect_true(file.exists(file.path(lib, "zigdownload", "libs")))

  unlink(record)
  log <- install_log(package, local_tempdir(), c(base_env, "RZIG_DOWNLOAD_ZIG=true", "RZIG_ZIG_VERSION=0.17.0"))
  expect_null(attr(log, "status"))
  expect_false(file.exists(record))
  expect_used_zig(log, compiler$version, home, "zig-stub-0.16.0")
})

test_that("a failed download stops the installation with a message", {
  skip_on_cran()
  skip_on_os("windows")
  compiler <- find_zig(required = FALSE)
  skip_if_not(isTRUE(compiler$supported), "no supported Zig compiler")
  package <- local_package("zigdownfail")
  suppressMessages(use_rzig(package))
  record <- file.path(local_tempdir(), "arguments")
  stub_fetch(package, normalizePath(compiler$path), record, fail = TRUE)
  env <- c(paste0("PATH=", shQuote(without_zig_path())), paste0("HOME=", shQuote(local_tempdir())),
    paste0("R_USER_CACHE_DIR=", shQuote(local_tempdir())), "ZIG=", "RZIG_ZIG_HOME=",
    "RZIG_DOWNLOAD_ZIG=true", "RZIG_ZIG_VERSION=0.17.0")
  log <- install_log(package, local_tempdir(), env)
  expect_false(is.null(attr(log, "status")))
  expect_identical(readLines(record)[[1L]], "0.17.0")
  expect_true(any(grepl("could not download a verified Zig 0.17.0", log, fixed = TRUE)))
})

test_that("configure downloads a real Zig release when RZIG_TEST_DOWNLOAD is set", {
  skip_on_cran()
  skip_on_os("windows")
  skip_if_not(identical(Sys.getenv("RZIG_TEST_DOWNLOAD"), "true"), "set RZIG_TEST_DOWNLOAD=true to download Zig")
  package <- local_package("zigrealdownload")
  suppressMessages(use_rzig(package))
  home <- local_tempdir()
  lib <- local_tempdir()
  log <- install_log(package, lib, c(paste0("PATH=", shQuote(without_zig_path())),
    paste0("HOME=", shQuote(local_tempdir())), paste0("RZIG_ZIG_HOME=", shQuote(home)), "ZIG=",
    "RZIG_DOWNLOAD_ZIG=true"))
  expect_null(attr(log, "status"))
  expect_true(any(grepl("using Zig 0.16.0 at", log, fixed = TRUE)))
})
