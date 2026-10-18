#' Run the Zig tests of a package
#'
#' Runs `zig build test` for the client package: the `test` blocks reached
#' from `src/rzig/src/tests.zig` are compiled for the host and run without R.
#' `tests.zig` imports the files whose tests should run, for example
#' `test { _ = @import("kernels.zig"); }`; files that use the `rzig` module
#' need R and cannot run there, so numerical kernels are best kept in files of
#' plain Zig. The package folder receives no build output.
#'
#' @param path Path to a package previously initialized with [use_rzig()].
#'
#' @return An object of class `rzig_zig_tests`: a list with `ok`, `failed`
#'   (the names of failed tests), `seconds` and `log`, invisibly. A failure
#'   also signals a warning.
#' @examples
#' \donttest{
#' if (isTRUE(find_zig(required = FALSE)$supported)) {
#'   package_path <- tempfile("rzig-tests-", tmpdir = tempdir())
#'   dir.create(package_path)
#'   writeLines(c("Package: examplepkg", "Version: 0.0.1"),
#'     file.path(package_path, "DESCRIPTION"))
#'   use_rzig(package_path)
#'   writeLines(c("const std = @import(\"std\");", "test \"addition\" {",
#'     "    try std.testing.expectEqual(4, 2 + 2);", "}"),
#'     file.path(package_path, "src", "rzig", "src", "tests.zig"))
#'   test_zig(package_path)
#'   unlink(package_path, recursive = TRUE)
#' }
#' }
#' @export
test_zig <- function(path) {
  info <- .rzig_package_info(path)
  zig_dir <- file.path(info$path, "src", "rzig")
  tests <- file.path(zig_dir, "src", "tests.zig")
  if (!file.exists(tests)) {
    stop(
      "no Zig tests: create src/rzig/src/tests.zig, for example with ",
      "`test { _ = @import(\"kernels.zig\"); }`, to run the test blocks of those files",
      call. = FALSE
    )
  }
  build <- .rzig_read_text(file.path(zig_dir, "build.zig")) %||% ""
  if (!grepl("\"test\"", build, fixed = TRUE)) {
    stop("src/rzig/build.zig defines no `test` step; update_rzig(path) installs one", call. = FALSE)
  }
  compiler <- find_zig()
  imports <- .rzig_imports_tool()$rzig_imports_option(info$path)
  work <- tempfile("rzig-zig-tests-")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE, force = TRUE), add = TRUE)
  # The global cache is kept for the session (RZIG_ZIG_CACHE overrides it), so
  # later calls reuse the compiled build runner and standard library.
  global_cache <- Sys.getenv("RZIG_ZIG_CACHE", unset = file.path(tempdir(), "rzig-zig-cache"))
  # `zig build` of Zig 0.17 has no --global-cache-dir; the variable reaches
  # the compiler on every platform when it is set in this process.
  previous <- Sys.getenv("ZIG_GLOBAL_CACHE_DIR", unset = NA_character_)
  Sys.setenv(ZIG_GLOBAL_CACHE_DIR = global_cache)
  on.exit(if (is.na(previous)) Sys.unsetenv("ZIG_GLOBAL_CACHE_DIR") else Sys.setenv(ZIG_GLOBAL_CACHE_DIR = previous), add = TRUE)
  started <- Sys.time()
  old <- setwd(zig_dir)
  on.exit(setwd(old), add = TRUE)
  log <- suppressWarnings(system2(
    compiler$path,
    c("build", "test", "--cache-dir", shQuote(file.path(work, "local")), "--summary", "all",
      if (nzchar(imports)) shQuote(paste0("-Drzig-imports=", imports))),
    stdout = TRUE, stderr = TRUE
  ))
  status <- attr(log, "status", exact = TRUE)
  log <- as.character(log)
  failed <- unique(sub("^.*'([^']+)' failed.*$", "\\1", grep("' failed", log, value = TRUE)))
  failed <- sub("^.*\\.test\\.", "", failed)
  result <- structure(list(
    ok = is.null(status) || identical(as.integer(status), 0L),
    failed = failed,
    seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    log = log
  ), class = "rzig_zig_tests")
  if (!result$ok) {
    warning(sprintf("the Zig tests of package %s failed; print the result for details", info$package),
      call. = FALSE)
  }
  invisible(result)
}

#' @export
print.rzig_zig_tests <- function(x, ...) {
  if (x$ok) {
    cat(sprintf("Zig tests passed in %.1f seconds\n", x$seconds))
  } else if (length(x$failed)) {
    cat("Zig tests failed:\n")
    for (name in x$failed) cat("  ", name, "\n", sep = "")
  } else {
    cat("Zig tests did not run:\n")
    cat(paste0("  ", utils::tail(x$log, 10L)), sep = "\n")
  }
  invisible(x)
}
