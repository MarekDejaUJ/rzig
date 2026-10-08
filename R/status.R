#' Report the state of a Zig-backed package
#'
#' Checks each step of the RZig workflow in a package and reports what is
#' present, what is missing and what is out of date: the `DESCRIPTION`
#' file, the scaffold written by [use_rzig()], the package author's Zig
#' source, the exported functions found by [scan_exports()], whether the
#' generated bindings match the current exports, and whether a supported Zig
#' compiler is available for installing the package.
#'
#' @param path Path to the package root.
#'
#' @return An object of class `rzig_status`: a data frame with the columns
#'   `step`, `ok` and `detail`, one row per check, with the attribute `path`.
#' @examples
#' package_path <- tempfile("rzig-status-", tmpdir = tempdir())
#' dir.create(package_path)
#' writeLines(c("Package: examplepkg", "Version: 0.0.1"),
#'   file.path(package_path, "DESCRIPTION"))
#' use_rzig(package_path)
#' rzig_status(package_path)
#' unlink(package_path, recursive = TRUE)
#' @export
rzig_status <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  rows <- list()
  add <- function(step, ok, detail) {
    rows[[length(rows) + 1L]] <<- data.frame(
      step = step, ok = ok, detail = detail, stringsAsFactors = FALSE
    )
  }

  info <- tryCatch(.rzig_package_info(path), error = function(error) NULL)
  if (is.null(info)) {
    add("DESCRIPTION", FALSE, "no DESCRIPTION with a Package field")
  } else {
    add("DESCRIPTION", TRUE, paste("package", info$package))
  }

  managed <- .rzig_managed_files
  present <- file.exists(file.path(path, managed))
  framework <- file.path(path, "src", "rzig", "framework", "rzig.zig")
  if (all(present) && file.exists(framework)) {
    add("Scaffold", TRUE, "build files, entry stub and framework sources present")
  } else {
    missing <- c(managed[!present], if (!file.exists(framework)) file.path("src", "rzig", "framework"))
    add("Scaffold", FALSE, paste("missing:", paste(missing, collapse = ", "), "; run use_rzig()"))
  }

  source_path <- .rzig_source_path(path)
  exports <- NULL
  if (!file.exists(source_path)) {
    add("Zig source", FALSE, paste("missing", file.path("src", "rzig", "src", "main.zig")))
    add("Exports", FALSE, "no source to scan")
  } else {
    add("Zig source", TRUE, file.path("src", "rzig", "src", "main.zig"))
    exports <- if (is.null(info)) NULL else tryCatch(scan_exports(path), error = function(error) error)
    if (is.null(exports)) {
      add("Exports", FALSE, "cannot scan without a package name")
    } else if (inherits(exports, "error")) {
      add("Exports", FALSE, conditionMessage(exports))
      exports <- NULL
    } else if (!length(exports)) {
      add("Exports", FALSE, "no public function marked with /// @export")
    } else {
      add("Exports", TRUE, paste(
        length(exports), "function(s):",
        paste(vapply(exports, function(item) item$name, character(1L)), collapse = ", ")
      ))
    }
  }

  if (!is.null(exports) && !is.null(info)) {
    bindings <- render_bindings(exports, info$package)
    manifest <- .rzig_normalize_newlines(.rzig_read_text(.rzig_manifest_path(path)))
    wrappers <- .rzig_normalize_newlines(.rzig_read_text(.rzig_wrapper_path(path)))
    namespace <- .rzig_normalize_newlines(.rzig_read_text(file.path(path, "NAMESPACE")))
    stale <- character()
    if (!identical(manifest, bindings$manifest)) stale <- c(stale, "manifest.zig")
    if (!identical(wrappers, bindings$wrappers)) stale <- c(stale, "R/rzig-wrappers.R")
    if (is.null(namespace) || !grepl(bindings$namespace, namespace, fixed = TRUE)) {
      stale <- c(stale, "NAMESPACE")
    }
    if (length(stale)) {
      add("Bindings", FALSE, paste("out of date:", paste(stale, collapse = ", "), "; run document()"))
    } else {
      add("Bindings", TRUE, "manifest, R wrappers and NAMESPACE block match the exports")
    }
  } else {
    add("Bindings", FALSE, "cannot be checked without exports")
  }

  compiler <- find_zig(required = FALSE)
  if (isTRUE(compiler$supported)) {
    add("Zig compiler", TRUE, sprintf("%s (version %s)", compiler$path, compiler$version))
  } else if (is.null(compiler$path)) {
    add("Zig compiler", FALSE, sprintf(
      "not found; Zig %s is needed to install the package", compiler$series
    ))
  } else {
    add("Zig compiler", FALSE, sprintf(
      "%s has version %s; rzig supports Zig %s", compiler$path,
      if (is.null(compiler$version)) "unknown" else compiler$version, compiler$series
    ))
  }

  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  structure(result, class = c("rzig_status", "data.frame"), path = path)
}

#' @export
print.rzig_status <- function(x, ...) {
  cat("RZig status of", attr(x, "path", exact = TRUE), "\n")
  for (index in seq_len(nrow(x))) {
    cat(sprintf(
      "  [%s] %-13s %s\n", if (x$ok[[index]]) "ok" else "--", x$step[[index]], x$detail[[index]]
    ))
  }
  invisible(x)
}
