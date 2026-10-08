.rzig_zig_series <- c(major = 0L, minor = 16L)

.rzig_zig_series_label <- function() {
  sprintf("%d.%d.x", .rzig_zig_series[["major"]], .rzig_zig_series[["minor"]])
}

.rzig_zig_supported <- function(version) {
  match <- regmatches(version, regexec("^([0-9]+)\\.([0-9]+)\\.([0-9]+)", version))[[1L]]
  if (length(match) != 4L) {
    return(FALSE)
  }
  found <- as.integer(match[2:3])
  found[[1L]] == .rzig_zig_series[["major"]] &&
    found[[2L]] == .rzig_zig_series[["minor"]]
}

.rzig_zig_candidates <- function() {
  candidates <- character()
  zig <- Sys.getenv("ZIG", unset = "")
  if (nzchar(zig)) {
    candidates <- c(candidates, path.expand(zig))
  }
  on_path <- unname(Sys.which("zig"))
  if (nzchar(on_path)) {
    candidates <- c(candidates, on_path)
  }
  home <- Sys.getenv("HOME", unset = "")
  if (nzchar(home)) {
    executable <- if (.Platform$OS.type == "windows") "zig.exe" else "zig"
    candidates <- c(
      candidates,
      Sys.glob(file.path(home, ".local", "share", "zig", "*", executable)),
      file.path(home, "zig", executable)
    )
  }
  unique(candidates)
}

#' Locate a supported Zig compiler
#'
#' Searches the environment variable `ZIG`, the `PATH`,
#' `~/.local/share/zig/*/zig` and `~/zig/zig`, in that order, and reports the
#' first Zig executable found, its version and whether rzig supports that
#' version. rzig itself runs without Zig: [use_rzig()], [scan_exports()] and
#' [document()] are pure R. A Zig compiler of the supported release series is
#' needed to install a package created with [use_rzig()].
#'
#' rzig 0.3.0 supports the Zig 0.16 release series (versions `0.16.x`). Zig
#' changes its language and standard library between release series, so a
#' newer or older compiler is reported as unsupported.
#'
#' @param required If `TRUE`, a missing or unsupported compiler is an error.
#'   If `FALSE`, the returned object records the problem instead.
#'
#' @return An object of class `rzig_compiler`: a list with `path` (character
#'   or `NULL`), `version` (character or `NULL`), `supported` (logical) and
#'   `series` (the supported release series, `"0.16.x"`).
#' @examples
#' find_zig(required = FALSE)
#' @export
find_zig <- function(required = TRUE) {
  if (length(required) != 1L || is.na(required)) {
    stop("`required` must be TRUE or FALSE", call. = FALSE)
  }
  result <- list(
    path = NULL,
    version = NULL,
    supported = FALSE,
    series = .rzig_zig_series_label()
  )
  class(result) <- "rzig_compiler"

  explicit <- Sys.getenv("ZIG", unset = "")
  if (nzchar(explicit) && file.access(path.expand(explicit), mode = 1L) != 0L) {
    result$problem <- paste0("ZIG does not name an executable: ", explicit)
    return(.rzig_compiler_result(result, required))
  }

  candidates <- .rzig_zig_candidates()
  candidates <- candidates[file.access(candidates, mode = 1L) == 0L]
  if (!length(candidates)) {
    result$problem <- paste0(
      "no Zig compiler found. rzig supports Zig ", result$series,
      "; download it from https://ziglang.org/download/, add it to PATH, ",
      "or set ZIG=/absolute/path/to/zig"
    )
    return(.rzig_compiler_result(result, required))
  }

  zig <- candidates[[1L]]
  version_output <- tryCatch(
    suppressWarnings(system2(zig, "version", stdout = TRUE, stderr = TRUE)),
    error = function(error) character()
  )
  version <- if (length(version_output)) trimws(version_output[[1L]]) else ""
  result$path <- zig
  if (!nzchar(version)) {
    result$problem <- paste0("Zig at ", zig, " did not report a version")
    return(.rzig_compiler_result(result, required))
  }
  result$version <- version
  result$supported <- .rzig_zig_supported(version)
  if (!result$supported) {
    result$problem <- paste0(
      "Zig ", version, " found at ", zig, ", but rzig supports Zig ",
      result$series, ". Download a supported release from ",
      "https://ziglang.org/download/ and set ZIG=/absolute/path/to/zig"
    )
  }
  .rzig_compiler_result(result, required)
}

.rzig_compiler_result <- function(result, required) {
  if (isTRUE(required) && !isTRUE(result$supported)) {
    stop(result$problem, call. = FALSE)
  }
  result
}

#' @export
print.rzig_compiler <- function(x, ...) {
  if (is.null(x$path)) {
    cat("Zig compiler: not found\n")
  } else if (isTRUE(x$supported)) {
    cat(sprintf("Zig compiler: %s (version %s, supported)\n", x$path, x$version))
  } else if (is.null(x$version)) {
    cat(sprintf("Zig compiler: %s (version unknown)\n", x$path))
  } else {
    cat(sprintf(
      "Zig compiler: %s (version %s, unsupported)\n", x$path, x$version
    ))
  }
  cat(sprintf("rzig supports the Zig %s release series.\n", x$series))
  if (!isTRUE(x$supported) && !is.null(x$problem)) {
    cat(strwrap(x$problem, exdent = 2), sep = "\n")
  }
  invisible(x)
}
