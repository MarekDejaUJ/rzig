#' Add a GitHub Actions workflow that checks the package with Zig
#'
#' Writes `.github/workflows/rzig-check.yaml`, a workflow that installs R and
#' Zig and runs `R CMD check --as-cran` on each operating system and Zig
#' version of its matrix. When `src/rzig/src/tests.zig` exists, the Zig tests
#' ([test_zig()]) run before the check. `.github` is added to
#' `.Rbuildignore`.
#'
#' @param path Path to a package previously initialized with [use_rzig()].
#' @param zig The Zig versions to test: releases of the series rzig supports
#'   (see [find_zig()]).
#' @param os The GitHub runners to test on.
#' @param overwrite If `TRUE`, replace an existing workflow file.
#'
#' @return The path of the workflow file, invisibly.
#' @examples
#' package_path <- tempfile("rzig-ci-", tmpdir = tempdir())
#' dir.create(package_path)
#' writeLines(c("Package: examplepkg", "Version: 0.0.1"),
#'   file.path(package_path, "DESCRIPTION"))
#' use_rzig(package_path)
#' use_rzig_ci(package_path, os = "ubuntu-latest")
#' unlink(package_path, recursive = TRUE)
#' @export
use_rzig_ci <- function(path, zig = c("0.16.0", "0.17.0"),
                        os = c("ubuntu-latest", "macos-latest", "windows-latest"),
                        overwrite = FALSE) {
  info <- .rzig_package_info(path)
  if (!is.character(zig) || !length(zig) || !all(vapply(zig, .rzig_zig_supported, logical(1L)))) {
    stop(sprintf("`zig` must name Zig releases of the series %s, for example \"0.16.0\"",
      .rzig_zig_series_label()), call. = FALSE)
  }
  if (!is.character(os) || !length(os) || !all(grepl("^[A-Za-z0-9._-]+$", os))) {
    stop("`os` must name GitHub runners, for example \"ubuntu-latest\"", call. = FALSE)
  }
  if (!file.exists(file.path(info$path, "src", "rzig", "build.zig"))) {
    stop("no RZig scaffold in ", info$path, "; run use_rzig(path) first", call. = FALSE)
  }
  target <- file.path(info$path, ".github", "workflows", "rzig-check.yaml")
  if (file.exists(target) && !isTRUE(overwrite)) {
    stop(".github/workflows/rzig-check.yaml exists; use overwrite = TRUE to replace it", call. = FALSE)
  }
  template <- .rzig_read_text(system.file("templates", "rzig-check.yaml", package = "rzig"))
  text <- sub("@OS@", paste(unique(os), collapse = ", "), template, fixed = TRUE)
  text <- sub("@ZIG@", paste0("\"", unique(zig), "\"", collapse = ", "), text, fixed = TRUE)
  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  .rzig_write_text(text, target)
  .rzig_add_buildignore(info$path, "^\\.github$")
  message("Wrote .github/workflows/rzig-check.yaml for package ", info$package)
  invisible(target)
}
