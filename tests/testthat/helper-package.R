local_package <- function(name = "testpkg", env = parent.frame()) {
  path <- tempfile(paste0("rzig-", name, "-"), tmpdir = tempdir())
  dir.create(path)
  writeLines(c(paste("Package:", name), "Version: 0.0.1"), file.path(path, "DESCRIPTION"))
  withr_defer <- function() unlink(path, recursive = TRUE, force = TRUE)
  do.call(on.exit, list(substitute(withr_defer()), add = TRUE), envir = env)
  assign("withr_defer", withr_defer, envir = env)
  path
}

read_bytes <- function(path) {
  rzig:::.rzig_read_text(path)
}

fixture_path <- function(...) {
  testthat::test_path("fixtures", ...)
}

with_fake_zig <- function(version, code) {
  skip_on_os("windows")
  script <- tempfile("fake-zig-")
  writeLines(c("#!/bin/sh", sprintf("printf '%%s\\n' '%s'", version)), script)
  Sys.chmod(script, mode = "0755")
  old <- Sys.getenv("ZIG", unset = NA)
  Sys.setenv(ZIG = script)
  on.exit({
    if (is.na(old)) Sys.unsetenv("ZIG") else Sys.setenv(ZIG = old)
    unlink(script)
  }, add = TRUE)
  force(code)
}

# Run R code in a fresh R process; the result keeps the exit status.
run_r <- function(code) {
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", "-e", shQuote(code)),
    stdout = TRUE, stderr = TRUE))
  structure(paste(out, collapse = "\n"), status = attr(out, "status"))
}

# An empty temporary directory removed when the calling test ends.
local_tempdir <- function(env = parent.frame()) {
  path <- tempfile("rzig-test-", tmpdir = tempdir())
  dir.create(path)
  do.call(on.exit, list(substitute(unlink(path, recursive = TRUE, force = TRUE), list(path = path)),
    add = TRUE), envir = env)
  path
}
