fresh_fetch <- function() {
  environment <- new.env(parent = baseenv())
  sys.source(system.file("zig", "tools", "fetch_zig.R", package = "rzig"), envir = environment,
    keep.source = FALSE)
  environment
}

can_hash <- function() {
  exists("sha256sum", envir = asNamespace("tools"), inherits = FALSE) ||
    requireNamespace("digest", quietly = TRUE)
}

# A tar.xz archive with one folder holding a script that answers `zig version`.
fake_zig_archive <- function(directory, top, version) {
  build <- file.path(directory, "build")
  dir.create(file.path(build, top), recursive = TRUE)
  zig <- file.path(build, top, "zig")
  writeLines(c("#!/bin/sh", sprintf("printf '%%s\\n' '%s'", version)), zig)
  Sys.chmod(zig, "0755")
  archive <- file.path(directory, paste0(top, ".tar.xz"))
  old <- setwd(build)
  on.exit(setwd(old), add = TRUE)
  utils::tar(archive, files = top, compression = "xz", tar = "internal")
  archive
}

local_env <- function(..., env = parent.frame()) {
  values <- list(...)
  old <- Sys.getenv(names(values), unset = NA, names = TRUE)
  do.call(Sys.setenv, values)
  restore <- function() {
    for (name in names(old)) {
      if (is.na(old[[name]])) Sys.unsetenv(name) else do.call(Sys.setenv, stats::setNames(list(old[[name]]), name))
    }
  }
  do.call(on.exit, list(substitute(restore()), add = TRUE), envir = env)
  assign("restore", restore, envir = env)
  invisible(old)
}

test_that("the pins cover six platforms of each downloadable release", {
  fetch <- fresh_fetch()
  expect_identical(names(fetch$rzig_fetch_pins), c("0.16.0", "0.17.0"))
  for (version in names(fetch$rzig_fetch_pins)) {
    pins <- fetch$rzig_fetch_pins[[version]]
    expect_setequal(names(pins), c(
      "aarch64-macos", "x86_64-macos", "aarch64-linux", "x86_64-linux", "aarch64-windows", "x86_64-windows"
    ))
    for (pin in pins) {
      expect_match(pin[[1L]], "^[0-9a-f]{64}$")
      expect_gt(as.numeric(pin[[2L]]), 4e7)
    }
    expect_true(rzig:::.rzig_zig_supported(version))
  }
  spec <- fetch$rzig_fetch_spec("0.16.0", "x86_64-windows")
  expect_identical(spec$file, "zig-x86_64-windows-0.16.0.zip")
  expect_identical(spec$executable, "zig.exe")
  expect_error(fetch$rzig_fetch_spec("0.15.2", "x86_64-linux"), "0.16.0 and 0.17.0")
})

test_that("platform names of R map to Zig's download keys", {
  fetch <- fresh_fetch()
  expect_identical(fetch$rzig_fetch_platform("Darwin", "arm64"), "aarch64-macos")
  expect_identical(fetch$rzig_fetch_platform("Linux", "x86_64"), "x86_64-linux")
  expect_identical(fetch$rzig_fetch_platform("Windows", "x86_64"), "x86_64-windows")
  expect_identical(fetch$rzig_fetch_platform("Linux", "aarch64"), "aarch64-linux")
  expect_error(fetch$rzig_fetch_platform("SunOS", "x86_64"), "macOS, Linux and Windows")
  expect_error(fetch$rzig_fetch_platform("Linux", "s390x"), "aarch64 and x86_64")
})

test_that("archive members outside the top folder are rejected", {
  fetch <- fresh_fetch()
  top <- "zig-x86_64-linux-0.16.0"
  expect_true(fetch$rzig_fetch_check_members(c(top, paste0(top, "/zig"), paste0(top, "/lib/std.zig")), top))
  expect_error(fetch$rzig_fetch_check_members(c(paste0(top, "/zig"), "../evil"), top), "unexpected paths")
  expect_error(fetch$rzig_fetch_check_members(c(paste0(top, "/zig"), "other/zig"), top), "unexpected paths")
  expect_error(fetch$rzig_fetch_check_members("/etc/passwd", top), "unexpected paths")
  expect_error(fetch$rzig_fetch_check_members(paste0(top, "/../../x"), top), "unexpected paths")
  expect_error(fetch$rzig_fetch_check_members(character(), top), "unexpected paths")
})

test_that("mirrors are tried before ziglang.org without touching the random stream", {
  fetch <- fresh_fetch()
  spec <- fetch$rzig_fetch_spec("0.16.0", "aarch64-linux")
  set.seed(1)
  before <- .Random.seed
  sources <- fetch$rzig_fetch_sources(spec, mirror_list = c("https://a.example/zig/", "https://b.example", "ftp://c"))
  expect_identical(.Random.seed, before)
  expect_length(sources, 3L)
  expect_setequal(sources[1:2], c(
    "https://a.example/zig/zig-aarch64-linux-0.16.0.tar.xz?source=r-rzig",
    "https://b.example/zig-aarch64-linux-0.16.0.tar.xz?source=r-rzig"
  ))
  expect_identical(sources[[3L]], "https://ziglang.org/download/0.16.0/zig-aarch64-linux-0.16.0.tar.xz")
  expect_identical(fetch$rzig_fetch_sources(spec, mirrors = FALSE), sources[[3L]])
})

test_that("a verified archive is installed once, and a corrupt download is skipped", {
  skip_on_os("windows")
  skip_if_not(can_hash(), "no SHA-256 implementation")
  fetch <- fresh_fetch()
  work <- local_tempdir()
  top <- "zig-aarch64-macos-0.16.0"
  archive <- fake_zig_archive(work, top, "0.16.0")
  fetch$rzig_fetch_pins <- list("0.16.0" = list(
    "aarch64-macos" = c(fetch$rzig_fetch_sha256(archive), as.character(file.size(archive)))
  ))
  requests <- character()
  download <- function(url, destination, quiet) {
    requests <<- c(requests, sub("^https://([^/]+).*$", "\\1", url))
    if (grepl("bad.example", url, fixed = TRUE)) {
      writeLines("not the archive", destination)
      return(TRUE)
    }
    file.copy(archive, destination, overwrite = TRUE)
  }
  home <- file.path(work, "home")
  path <- fetch$rzig_fetch_install("0.16.0", home, platform = "aarch64-macos", download = download,
    mirror_list = "https://bad.example/zig", inform = function(...) NULL)
  expect_identical(requests, c("bad.example", "ziglang.org"))
  expect_identical(path, normalizePath(file.path(home, top, "zig"), winslash = "/"))
  expect_identical(fetch$rzig_fetch_version(path), "0.16.0")
  receipt <- read.dcf(file.path(home, top, fetch$rzig_fetch_receipt))
  expect_identical(unname(receipt[1L, "Archive-SHA256"]), fetch$rzig_fetch_pins[["0.16.0"]][["aarch64-macos"]][[1L]])
  expect_identical(list.files(home, all.files = TRUE, no.. = TRUE), top)

  requests <- character()
  again <- fetch$rzig_fetch_install("0.16.0", home, platform = "aarch64-macos", download = download,
    mirror_list = "https://bad.example/zig", inform = function(...) NULL)
  expect_identical(again, path)
  expect_length(requests, 0L)

  writeLines("Version: 0.16.0", file.path(home, top, fetch$rzig_fetch_receipt))
  expect_error(fetch$rzig_fetch_install("0.16.0", home, platform = "aarch64-macos", download = download,
    inform = function(...) NULL), "not a complete Zig 0.16.0 installation")
})

test_that("an archive that no source provides stops with the attempts and leaves nothing", {
  skip_if_not(can_hash(), "no SHA-256 implementation")
  fetch <- fresh_fetch()
  home <- file.path(local_tempdir(), "home")
  download <- function(url, destination, quiet) {
    if (grepl("ziglang.org", url, fixed = TRUE)) return(FALSE)
    writeLines("not the archive", destination)
    TRUE
  }
  expect_error(fetch$rzig_fetch_install("0.17.0", home, platform = "x86_64-linux", download = download,
    mirror_list = "https://bad.example", inform = function(...) NULL),
    "bad.example (size or SHA-256 differs from the pinned archive), ziglang.org (download failed)", fixed = TRUE)
  expect_identical(list.files(home, all.files = TRUE, no.. = TRUE), character())
  dir.create(file.path(home, "zig-x86_64-linux-0.17.0.lock"))
  expect_error(fetch$rzig_fetch_install("0.17.0", home, platform = "x86_64-linux", download = download,
    inform = function(...) NULL), "another installation")
})

test_that("install_zig validates its arguments and zig_home follows RZIG_ZIG_HOME", {
  expect_error(install_zig("0.15.2", dir = local_tempdir()), "0.16.0 and 0.17.0")
  expect_error(install_zig(c("0.16.0", "0.17.0")), "one Zig release")
  expect_error(install_zig("0.16.0", dir = ""), "one folder")
  folder <- local_tempdir()
  local_env(RZIG_ZIG_HOME = folder)
  expect_identical(zig_home(), normalizePath(folder, winslash = "/"))
  restore()
  cache <- local_tempdir()
  local_env(RZIG_ZIG_HOME = "", R_USER_CACHE_DIR = cache)
  expect_identical(zig_home(), normalizePath(file.path(cache, "R", "rzig", "zig"), winslash = "/", mustWork = FALSE))
  expect_identical(uninstall_zig(), character())
})

test_that("find_zig finds a compiler installed in zig_home after the PATH", {
  skip_on_os("windows")
  cache <- local_tempdir()
  home <- file.path(cache, "R", "rzig", "zig", "zig-aarch64-macos-0.16.0")
  dir.create(home, recursive = TRUE)
  writeLines(c("#!/bin/sh", "printf '%s\\n' '0.16.0'"), file.path(home, "zig"))
  Sys.chmod(file.path(home, "zig"), "0755")
  path <- strsplit(Sys.getenv("PATH"), .Platform$path.sep, fixed = TRUE)[[1L]]
  path <- path[!file.exists(file.path(path, "zig"))]
  local_env(ZIG = "", RZIG_ZIG_HOME = "", R_USER_CACHE_DIR = cache, HOME = local_tempdir(),
    PATH = paste(path, collapse = .Platform$path.sep))
  Sys.unsetenv("ZIG")
  found <- find_zig()
  expect_identical(normalizePath(found$path), normalizePath(file.path(home, "zig")))
  expect_identical(found$version, "0.16.0")
})

test_that("configure finds a compiler installed in zig_home", {
  skip_on_cran()
  skip_on_os("windows")
  compiler <- find_zig(required = FALSE)
  skip_if_not(isTRUE(compiler$supported), "no supported Zig compiler")
  cache <- local_tempdir()
  zig_folder <- file.path(cache, "R", "rzig", "zig")
  dir.create(zig_folder, recursive = TRUE)
  linked <- file.path(zig_folder, paste0("zig-test-", compiler$version))
  file.symlink(dirname(normalizePath(compiler$path)), linked)
  package <- local_package("zighome")
  suppressMessages(use_rzig(package))
  path <- strsplit(Sys.getenv("PATH"), .Platform$path.sep, fixed = TRUE)[[1L]]
  path <- path[!file.exists(file.path(path, "zig"))]
  lib <- local_tempdir()
  log <- suppressWarnings(system2(file.path(R.home("bin"), "R"),
    c("CMD", "INSTALL", paste0("--library=", shQuote(lib)), shQuote(package)),
    stdout = TRUE, stderr = TRUE,
    env = c(paste0("PATH=", shQuote(paste(path, collapse = .Platform$path.sep))),
      paste0("HOME=", shQuote(local_tempdir())), paste0("R_USER_CACHE_DIR=", shQuote(cache)),
      "ZIG=", "RZIG_ZIG_HOME=")))
  expect_null(attr(log, "status"))
  expected <- file.path(normalizePath(zig_folder), basename(linked), "zig")
  expect_true(any(grepl(sprintf("using Zig %s at %s", compiler$version, expected), log, fixed = TRUE)))
})
