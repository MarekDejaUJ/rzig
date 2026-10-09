#' Report the state of a Zig-backed package
#'
#' Checks each step of the RZig workflow in a package and reports what is
#' present, what is missing and what would make the installation fail:
#'
#' * **DESCRIPTION**: the package name and a valid version.
#' * **Scaffold**: the files written by [use_rzig()], framework sources that
#'   match the installed rzig, and executable `configure` and `cleanup`
#'   scripts.
#' * **Zig source**: `src/rzig/src/main.zig` with the registration block and
#'   the panic handler of rzig.
#' * **Exports**: the exported functions found by [scan_exports()], with
#'   every argument and return type that the boundary rejects, more than 32
#'   arguments, misuse of `rzig.Mut([]f64)`, error sets other than
#'   `rzig.Error`, and R functions of the same name elsewhere in `R/`.
#' * **Bindings**: whether the files written by [document()] match the
#'   exports.
#' * **Zig compiler**: a compiler of a supported release series
#'   ([find_zig()]).
#' * **C toolchain**: the C compiler of R, `make` and the R headers.
#' * **Build** (only with `build = TRUE`): the result of [build_zig()].
#'
#' Every check except the build runs in R without compiling anything.
#'
#' @param path Path to the package root.
#' @param build If `TRUE`, also compile and install the package with
#'   [build_zig()] when every other check passes.
#'
#' @return An object of class `rzig_status`: a data frame with the columns
#'   `step`, `ok` and `detail`, one row per check, with the attributes
#'   `path`, `package` and, with `build = TRUE`, `build` (the
#'   [rzig_build][build_zig()] object).
#' @examples
#' package_path <- tempfile("rzig-status-", tmpdir = tempdir())
#' dir.create(package_path)
#' writeLines(c("Package: examplepkg", "Version: 0.0.1"),
#'   file.path(package_path, "DESCRIPTION"))
#' use_rzig(package_path)
#' rzig_status(package_path)
#' main <- file.path(package_path, "src", "rzig", "src", "main.zig")
#' cat("/// @export\npub fn half(x: f32) f32 {\n    return x / 2;\n}\n",
#'   file = main, append = TRUE)
#' rzig_status(package_path)
#' unlink(package_path, recursive = TRUE)
#' @export
rzig_status <- function(path, build = FALSE) {
  if (length(build) != 1L || is.na(build)) {
    stop("`build` must be TRUE or FALSE", call. = FALSE)
  }
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  rows <- list()
  add <- function(step, problems = character(), summary = "", notes = character()) {
    detail <- if (length(problems)) problems else c(summary, notes)
    detail <- detail[nzchar(detail)]
    rows[[length(rows) + 1L]] <<- data.frame(
      step = step, ok = !length(problems),
      detail = paste(detail, collapse = "\n"), stringsAsFactors = FALSE
    )
  }

  description <- .rzig_check_description(path)
  info <- tryCatch(.rzig_package_info(path), error = function(error) NULL)
  add(
    "DESCRIPTION", description$problems,
    if (!is.null(info)) paste("package", info$package) else "",
    description$notes
  )
  label <- if (is.null(info)) basename(path) else info$package

  scaffold <- .rzig_check_scaffold(path, info$package)
  scaffold_ok <- !length(scaffold$problems) ||
    !any(startsWith(scaffold$problems, "missing:"))
  add("Scaffold", scaffold$problems, "build files and framework sources present", scaffold$notes)

  source_path <- .rzig_source_path(path)
  exports <- NULL
  if (!file.exists(source_path)) {
    add("Zig source", paste("missing", file.path("src", "rzig", "src", "main.zig"), "; run use_rzig()"))
    add("Exports", "no Zig source to scan")
  } else {
    add("Zig source", .rzig_check_source(path)$problems, file.path("src", "rzig", "src", "main.zig"))
    scanned <- if (is.null(info)) {
      simpleError("cannot scan without a package name")
    } else {
      tryCatch(scan_exports(path), error = function(error) error)
    }
    if (inherits(scanned, "error")) {
      add("Exports", conditionMessage(scanned))
    } else if (!length(scanned)) {
      add("Exports", "no public function marked with /// @export")
    } else {
      exports <- scanned
      types <- .rzig_check_exports(exports)
      conflicts <- .rzig_check_r_conflicts(path, exports)
      names <- vapply(exports, function(item) item$name, character(1L))
      add(
        "Exports", c(types$problems, conflicts$problems),
        paste0(
          length(exports), " function", if (length(exports) == 1L) "" else "s", ": ",
          paste(names, collapse = ", ")
        ),
        types$notes
      )
    }
  }

  if (!is.null(exports) && !is.null(info) && scaffold_ok) {
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
    add(
      "Bindings",
      if (length(stale)) paste0("out of date: ", paste(stale, collapse = ", "), "; run document()"),
      "generated files match the exports"
    )
  } else {
    add("Bindings", "cannot be checked without a scaffold and exports")
  }

  compiler <- find_zig(required = FALSE)
  if (isTRUE(compiler$supported)) {
    add("Zig compiler", summary = sprintf("%s (version %s)", compiler$path, compiler$version))
  } else if (is.null(compiler$path)) {
    add("Zig compiler", sprintf("not found; Zig %s is needed to install the package", compiler$series))
  } else {
    add("Zig compiler", sprintf(
      "%s has version %s; rzig supports Zig %s", compiler$path,
      if (is.null(compiler$version)) "unknown" else compiler$version, compiler$series
    ))
  }

  toolchain <- .rzig_check_toolchain()
  add("C toolchain", toolchain$problems, "", toolchain$notes)

  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  built <- NULL
  if (isTRUE(build)) {
    if (all(result$ok)) {
      built <- build_zig(path, preflight = FALSE)
      problems <- if (built$ok) character() else .rzig_build_summary(built)
      extra <- data.frame(
        step = "Build", ok = built$ok,
        detail = if (built$ok) sprintf("compiled and installed in %.1f seconds", built$seconds) else
          paste(problems, collapse = "\n"),
        stringsAsFactors = FALSE
      )
    } else {
      extra <- data.frame(step = "Build", ok = FALSE,
        detail = "not attempted; fix the failed checks first", stringsAsFactors = FALSE)
    }
    result <- rbind(result, extra)
  }
  structure(
    result, class = c("rzig_status", "data.frame"),
    path = path, package = label, build = built
  )
}

#' @export
print.rzig_status <- function(x, ...) {
  cat(sprintf("RZig status of package %s\n", attr(x, "package", exact = TRUE)))
  width <- max(40L, getOption("width", 80L) - 2L)
  for (index in seq_len(nrow(x))) {
    lines <- strsplit(x$detail[[index]], "\n", fixed = TRUE)[[1L]]
    if (!length(lines)) lines <- ""
    prefix <- sprintf("  [%s] %-13s ", if (x$ok[[index]]) "ok" else "--", x$step[[index]])
    indent <- strrep(" ", nchar(prefix))
    for (position in seq_along(lines)) {
      wrapped <- strwrap(lines[[position]], width = width - nchar(prefix))
      if (!length(wrapped)) wrapped <- ""
      first <- if (position == 1L) prefix else indent
      cat(first, wrapped[[1L]], "\n", sep = "")
      for (more in wrapped[-1L]) cat(indent, "  ", more, "\n", sep = "")
    }
  }
  failed <- x$step[!x$ok]
  if (length(failed)) {
    cat(sprintf("%d of %d checks failed: %s\n", length(failed), nrow(x), paste(failed, collapse = ", ")))
  }
  invisible(x)
}
