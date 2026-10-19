.rzig_zig_series <- list(major = 0L, minor = c(16L, 17L))

.rzig_zig_series_label <- function() {
  paste(sprintf("%d.%d.x", .rzig_zig_series$major, .rzig_zig_series$minor), collapse = " or ")
}

# A Zig release of a supported series. The version must be exactly
# MAJOR.MINOR.PATCH: development builds (0.17.0-dev.N+hash) are rejected,
# because their language and standard library can differ from the release.
.rzig_zig_supported <- function(version) {
  match <- regmatches(version, regexec("^([0-9]+)\\.([0-9]+)\\.([0-9]+)$", version))[[1L]]
  if (length(match) != 4L) {
    return(FALSE)
  }
  found <- as.integer(match[2:3])
  found[[1L]] == .rzig_zig_series$major &&
    found[[2L]] %in% .rzig_zig_series$minor
}

# Compilers searched when ZIG is unset, in order.
.rzig_zig_candidates <- function() {
  candidates <- character()
  on_path <- unname(Sys.which("zig"))
  if (nzchar(on_path)) {
    candidates <- c(candidates, on_path)
  }
  executable <- if (.Platform$OS.type == "windows") "zig.exe" else "zig"
  candidates <- c(candidates, sort(Sys.glob(file.path(zig_home(), "zig-*", executable))))
  home <- Sys.getenv("HOME", unset = "")
  if (nzchar(home)) {
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
#' Uses the compiler named by the environment variable `ZIG` when it is set.
#' Otherwise searches the `PATH`, the installations of [install_zig()] in
#' [zig_home()], `~/.local/share/zig/*/zig` and `~/zig/zig`, in that order,
#' and reports the first compiler of a supported release series; when none is supported, it reports the first compiler found and why
#' it is rejected. rzig itself runs without Zig: [use_rzig()], [scan_exports()] and
#' [document()] are pure R. A Zig compiler of the supported release series is
#' needed to install a package created with [use_rzig()].
#'
#' rzig supports the Zig 0.16 and 0.17 release series (versions
#' `0.16.x` and `0.17.x`). Zig changes its language and standard library
#' between release series, so a newer or older compiler is reported as
#' unsupported. Development builds such as `0.17.0-dev.1234+abcdef` are
#' unsupported too: their language and standard library can differ from the
#' release.
#'
#' @param required If `TRUE`, a missing or unsupported compiler is an error.
#'   If `FALSE`, the returned object records the problem instead.
#'
#' @return An object of class `rzig_compiler`: a list with `path` (character
#'   or `NULL`), `version` (character or `NULL`), `supported` (logical) and
#'   `series` (the supported release series, `"0.16.x or 0.17.x"`).
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
  if (nzchar(explicit)) {
    explicit <- path.expand(explicit)
    if (file.access(explicit, mode = 1L) != 0L) {
      result$problem <- paste0("ZIG does not name an executable: ", explicit)
      return(.rzig_compiler_result(result, required))
    }
    return(.rzig_compiler_result(.rzig_compiler_probe(result, explicit), required))
  }

  candidates <- .rzig_zig_candidates()
  candidates <- candidates[file.access(candidates, mode = 1L) == 0L]
  if (!length(candidates)) {
    result$problem <- paste0(
      "no Zig compiler found. rzig supports Zig ", result$series,
      "; install it with install_zig(), or download it from https://ziglang.org/download/ ",
      "and add it to PATH or set ZIG=/absolute/path/to/zig"
    )
    return(.rzig_compiler_result(result, required))
  }

  # The first supported compiler wins, so an old zig on PATH does not hide a
  # supported one in the usual install locations.
  probes <- list()
  for (zig in candidates) {
    probe <- .rzig_compiler_probe(result, zig)
    if (isTRUE(probe$supported)) return(.rzig_compiler_result(probe, required))
    probes[[length(probes) + 1L]] <- probe
  }
  result <- probes[[1L]]
  if (length(probes) > 1L) {
    others <- vapply(probes[-1L], function(probe) {
      sprintf("%s (%s)", probe$path, if (is.null(probe$version)) "no version" else probe$version)
    }, character(1L))
    result$problem <- paste0(result$problem, ". Other compilers found: ", paste(others, collapse = ", "))
  }
  .rzig_compiler_result(result, required)
}

# Run `zig version` and record the version and whether it is supported.
.rzig_compiler_probe <- function(result, zig) {
  version_output <- tryCatch(
    suppressWarnings(system2(zig, "version", stdout = TRUE, stderr = TRUE, timeout = 30)),
    error = function(error) character()
  )
  version <- if (length(version_output)) trimws(version_output[[1L]]) else ""
  result$path <- zig
  if (!nzchar(version) || !is.null(attr(version_output, "status"))) {
    result$problem <- paste0("Zig at ", zig, " did not report a version")
    return(result)
  }
  result$version <- version
  result$supported <- .rzig_zig_supported(version)
  if (!result$supported) {
    kind <- if (grepl("-", version, fixed = TRUE)) "a development build" else "an unsupported release series"
    result$problem <- paste0(
      "Zig ", version, " found at ", zig, " is ", kind, "; rzig supports releases of Zig ",
      result$series, ". Download a supported release from ",
      "https://ziglang.org/download/ and set ZIG=/absolute/path/to/zig"
    )
  }
  result
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
  cat(sprintf("rzig supports Zig %s.\n", x$series))
  if (!isTRUE(x$supported) && !is.null(x$problem)) {
    cat(strwrap(x$problem, exdent = 2), sep = "\n")
  }
  invisible(x)
}
