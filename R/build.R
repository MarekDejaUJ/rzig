#' Compile and install a Zig-backed package, and report the first errors
#'
#' Runs the checks of [rzig_status()], then installs a copy of the package
#' with `R CMD INSTALL` into a library, using the Zig compiler reported by
#' [find_zig()]. The complete installation log is kept, and the errors of
#' the Zig compiler, the C compiler, the linker and the load test are
#' extracted with their files and lines, so a failed build names its cause
#' instead of the bare "non-zero exit status" of [utils::install.packages()].
#'
#' The package is built from a copy in the session temporary directory, so
#' the package source receives no object files or compiler caches. The
#' installation needs a supported Zig compiler and the C toolchain of R.
#'
#' @param path Path to the package root.
#' @param lib The library to install into. By default a new library in the
#'   session temporary directory; [library()] then needs
#'   `lib.loc = build$library`.
#' @param preflight If `TRUE`, run the checks of [rzig_status()] first and
#'   stop before compiling when one of them fails.
#'
#' @return An object of class `rzig_build`: a list with `ok` (logical),
#'   `package`, `step` (`"preflight"`, `"configure"`, `"compile"`,
#'   `"link"`, `"load"`, `"install"` or `NA` on success), `errors` (a data
#'   frame with the columns `file`, `line`, `column`, `message` and
#'   `function_name`), `problems` (failed checks before compilation),
#'   `library`, `zig` (the [rzig_compiler][find_zig()] used), `seconds` and
#'   `log` (the complete output of `R CMD INSTALL`). A failed build also
#'   signals a warning.
#' @examples
#' package_path <- tempfile("rzig-build-", tmpdir = tempdir())
#' dir.create(package_path)
#' writeLines(c("Package: examplepkg", "Version: 0.0.1"),
#'   file.path(package_path, "DESCRIPTION"))
#' use_rzig(package_path)
#'
#' # A change to main.zig without document() is caught before compiling.
#' main <- file.path(package_path, "src", "rzig", "src", "main.zig")
#' cat("/// @export\npub fn twice(x: f64) f64 {\n    return 2 * x;\n}\n",
#'   file = main, append = TRUE)
#' result <- suppressWarnings(build_zig(package_path))
#' result
#'
#' # With a supported Zig compiler, the regenerated package compiles; the
#' # compilation takes several seconds.
#' \donttest{
#' if (isTRUE(find_zig(required = FALSE)$supported)) {
#'   document(package_path)
#'   result <- build_zig(package_path)
#'   result
#' }
#' }
#' unlink(package_path, recursive = TRUE)
#' @export
build_zig <- function(path, lib = NULL, preflight = TRUE) {
  if (length(preflight) != 1L || is.na(preflight)) {
    stop("`preflight` must be TRUE or FALSE", call. = FALSE)
  }
  info <- .rzig_package_info(path)
  path <- info$path
  compiler <- find_zig(required = FALSE)
  result <- structure(
    list(
      ok = FALSE, package = info$package, step = NA_character_,
      errors = .rzig_empty_errors(), problems = character(),
      library = NULL, zig = compiler, seconds = NA_real_, log = character()
    ),
    class = "rzig_build"
  )

  if (isTRUE(preflight)) {
    status <- rzig_status(path)
    failed <- status[!status$ok, , drop = FALSE]
    if (nrow(failed)) {
      result$step <- "preflight"
      result$problems <- paste0(failed$step, ": ", gsub("\n", "; ", failed$detail, fixed = TRUE))
      return(.rzig_build_fail(result))
    }
  } else if (!isTRUE(compiler$supported)) {
    result$step <- "preflight"
    result$problems <- paste0("Zig compiler: ", compiler$problem)
    return(.rzig_build_fail(result))
  }

  workspace <- tempfile("rzig-build-")
  dir.create(workspace)
  on.exit(unlink(workspace, recursive = TRUE, force = TRUE), add = TRUE)
  copy <- file.path(workspace, info$package)
  .rzig_copy_package(path, copy)

  if (is.null(lib)) lib <- tempfile("rzig-library-")
  dir.create(lib, recursive = TRUE, showWarnings = FALSE)
  lib <- normalizePath(lib, winslash = "/", mustWork = TRUE)
  result$library <- lib

  old <- Sys.getenv("ZIG", unset = NA)
  Sys.setenv(ZIG = compiler$path)
  on.exit(if (is.na(old)) Sys.unsetenv("ZIG") else Sys.setenv(ZIG = old), add = TRUE)
  started <- Sys.time()
  log <- suppressWarnings(system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "INSTALL", "--no-multiarch", paste0("--library=", shQuote(lib)), shQuote(copy)),
    stdout = TRUE, stderr = TRUE
  ))
  result$seconds <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  status <- attr(log, "status", exact = TRUE)
  log <- as.character(log)
  log <- gsub(paste0(normalizePath(workspace, winslash = "/"), "/"), "", log, fixed = TRUE, useBytes = TRUE)
  result$log <- log
  if (is.null(status) || identical(as.integer(status), 0L)) {
    result$ok <- TRUE
    return(result)
  }
  parsed <- .rzig_parse_build_log(log, info$package, lib)
  result$step <- parsed$step
  result$errors <- .rzig_attach_functions(parsed$errors, path, info$package)
  .rzig_build_fail(result)
}

.rzig_build_fail <- function(result) {
  warning(sprintf(
    "the build of package %s failed at the %s step; print the result for the errors",
    result$package, result$step
  ), call. = FALSE)
  result
}

.rzig_empty_errors <- function() {
  data.frame(
    file = character(), line = integer(), column = integer(),
    message = character(), function_name = character(), stringsAsFactors = FALSE
  )
}

.rzig_copy_package <- function(source, destination) {
  files <- list.files(source, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  skip <- paste0(
    "(^|/)(\\.git|\\.Rproj\\.user|\\.zig-cache|\\.zig-global-cache|zig-out)(/|$)|",
    "^src/.*\\.(o|so|dll|dylib|a)$|^src/Makevars(\\.win)?$|\\.Rcheck(/|$)"
  )
  files <- files[!grepl(skip, files)]
  for (file in files) {
    target <- file.path(destination, file)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    file.copy(file.path(source, file), target, copy.mode = TRUE, copy.date = TRUE)
  }
  invisible(destination)
}

# ---------------------------------------------------------------------------
# Log parsing

.rzig_location_pattern <- "^(.+?):([0-9]+):([0-9]+): (fatal error|error): (.*)$"

.rzig_parse_build_log <- function(log, package = NULL, lib = NULL) {
  errors <- .rzig_empty_errors()
  add <- function(file, line, column, message) {
    errors[nrow(errors) + 1L, ] <<- list(file, line, column, message, NA_character_)
  }
  clean <- function(text) {
    if (!is.null(lib)) text <- gsub(lib, "<library>", text, fixed = TRUE, useBytes = TRUE)
    trimws(text)
  }

  step <- "install"
  configure_failed <- grep("^ERROR: configuration failed", log)
  if (length(configure_failed)) {
    step <- "configure"
    end <- configure_failed[[1L]] - 1L
    start <- end
    while (start > 1L && !grepl("^\\*", log[[start - 1L]])) start <- start - 1L
    lines <- log[seq.int(start, length.out = max(0L, end - start + 1L))]
    lines <- lines[nzchar(trimws(lines))]
    if (length(lines)) add(NA_character_, NA_integer_, NA_integer_, clean(paste(lines, collapse = "\n")))
    return(list(step = step, errors = errors))
  }

  located <- regmatches(log, regexec(.rzig_location_pattern, log, perl = TRUE))
  for (index in seq_along(located)) {
    match <- located[[index]]
    if (length(match) != 6L) next
    message <- match[[6L]]
    column <- nchar(log[[index]]) - nchar(message)
    following <- index + 1L
    while (following <= length(log) &&
           nchar(log[[following]]) > column &&
           grepl(paste0("^[[:space:]]{", column, ",}[^[:space:]]"), log[[following]])) {
      message <- paste(message, trimws(log[[following]]), sep = "\n")
      following <- following + 1L
    }
    add(
      .rzig_package_file(match[[2L]], package),
      as.integer(match[[3L]]), as.integer(match[[4L]]), clean(message)
    )
  }
  if (nrow(errors)) {
    errors <- errors[!duplicated(errors[, c("file", "line", "column", "message")]), , drop = FALSE]
    rownames(errors) <- NULL
    return(list(step = "compile", errors = errors))
  }

  linker <- grep("undefined reference to|Undefined symbols for architecture|^ld(\\.lld)?: (error|symbol)|unresolved external", log)
  if (length(linker)) {
    for (index in utils::head(linker, 5L)) add(NA_character_, NA_integer_, NA_integer_, clean(log[[index]]))
    return(list(step = "link", errors = errors))
  }

  load <- grep("package or namespace load failed|unable to load shared object", log)
  if (length(load)) {
    lines <- log[seq.int(load[[1L]], min(length(log), load[[1L]] + 3L))]
    lines <- lines[!grepl("^Error: loading failed|^Execution halted|^ERROR:", lines)]
    message <- clean(paste(lines, collapse = "\n"))
    if (grepl("rzig_init", message, fixed = TRUE)) {
      message <- paste(
        message,
        "The symbol rzig_init is missing: main.zig needs `comptime { rzig.registerModule(@This()); }`.",
        sep = "\n"
      )
    }
    add(NA_character_, NA_integer_, NA_integer_, message)
    return(list(step = "load", errors = errors))
  }

  failure <- grep("^ERROR: ", log)
  if (length(failure)) {
    end <- failure[[1L]]
    lines <- log[seq.int(max(1L, end - 10L), end)]
    add(NA_character_, NA_integer_, NA_integer_, clean(paste(lines, collapse = "\n")))
  }
  list(step = step, errors = errors)
}

# Map a path reported by the Zig or C compiler to a path in the package.
.rzig_package_file <- function(file, package) {
  file <- gsub("\\\\", "/", file)
  if (!is.null(package) && grepl("^(/|[A-Za-z]:)", file)) {
    marker <- paste0("/", package, "/")
    positions <- gregexpr(marker, file, fixed = TRUE)[[1L]]
    if (positions[[1L]] > 0L) {
      return(substring(file, max(positions) + nchar(marker)))
    }
  }
  if (grepl("^(src|framework|tools)/|^build\\.zig", file)) return(file.path("src", "rzig", file))
  if (grepl("^[^/]+\\.(c|h)$", file)) return(file.path("src", file))
  file
}

.rzig_attach_functions <- function(errors, path, package) {
  if (!nrow(errors)) return(errors)
  exports <- tryCatch(scan_exports(path), error = function(error) list())
  names <- vapply(exports, function(item) item$name, character(1L))
  lines <- vapply(exports, function(item) as.integer(item$line), integer(1L))
  for (index in seq_len(nrow(errors))) {
    match <- regmatches(errors$message[[index]], regexec("function `([^`]+)`", errors$message[[index]]))[[1L]]
    if (length(match) == 2L) {
      errors$function_name[[index]] <- match[[2L]]
    } else if (identical(errors$file[[index]], file.path("src", "rzig", "src", "main.zig")) && length(lines)) {
      before <- which(lines <= errors$line[[index]])
      if (length(before)) errors$function_name[[index]] <- names[[max(before)]]
    }
  }
  errors
}

.rzig_build_summary <- function(x) {
  if (length(x$problems)) return(x$problems)
  if (!nrow(x$errors)) return(sprintf("failed at the %s step; see $log", x$step))
  vapply(seq_len(nrow(x$errors)), function(index) {
    location <- if (is.na(x$errors$file[[index]])) "" else
      sprintf("%s:%d:%d: ", x$errors$file[[index]], x$errors$line[[index]], x$errors$column[[index]])
    paste0(location, gsub("\n", " ", x$errors$message[[index]], fixed = TRUE))
  }, character(1L))
}

#' @export
print.rzig_build <- function(x, ...) {
  width <- max(40L, getOption("width", 80L) - 4L)
  if (x$ok) {
    cat(sprintf("Build of package %s: succeeded in %.1f seconds\n", x$package, x$seconds))
    cat(sprintf("Zig compiler: %s (version %s)\n", x$zig$path, x$zig$version))
    temporary <- startsWith(x$library, normalizePath(tempdir(), winslash = "/"))
    cat(if (temporary) "Installed into a library in the session temporary directory\n" else
      sprintf("Installed into %s\n", x$library))
    return(invisible(x))
  }
  if (identical(x$step, "preflight")) {
    cat(sprintf("Build of package %s: not started; checks before compilation failed\n", x$package))
    for (problem in x$problems) {
      wrapped <- strwrap(problem, width = width)
      cat("  ", wrapped[[1L]], "\n", sep = "")
      for (more in wrapped[-1L]) cat("    ", more, "\n", sep = "")
    }
    return(invisible(x))
  }
  cat(sprintf("Build of package %s: failed at the %s step\n", x$package, x$step))
  shown <- utils::head(seq_len(nrow(x$errors)), 5L)
  for (index in shown) {
    error <- x$errors[index, ]
    where <- if (is.na(error$file)) "" else sprintf("%s:%d:%d", error$file, error$line, error$column)
    if (!is.na(error$function_name)) {
      where <- paste0(where, if (nzchar(where)) " " else "", sprintf("(function %s)", error$function_name))
    }
    if (nzchar(where)) cat("  ", where, "\n", sep = "")
    for (line in strsplit(error$message, "\n", fixed = TRUE)[[1L]]) {
      for (wrapped in strwrap(line, width = width)) cat("    ", wrapped, "\n", sep = "")
    }
  }
  if (nrow(x$errors) > length(shown)) {
    cat(sprintf("  ... and %d more errors\n", nrow(x$errors) - length(shown)))
  }
  cat(sprintf("The complete installation log (%d lines) is in $log.\n", length(x$log)))
  invisible(x)
}
