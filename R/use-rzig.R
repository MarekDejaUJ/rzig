#' Add RZig to a package
#'
#' Creates the Zig source tree, the portable build files, the native entry
#' stub and a working `hello_zig()` example in an existing package, then
#' generates the bindings with [document()]. The function is pure R; a Zig
#' compiler of the supported release series (see [find_zig()]) is needed
#' only when the package is installed.
#'
#' The files written below the package root are: `configure`,
#' `configure.win`, `cleanup`, `cleanup.win`, `src/entry.c`,
#' `src/Makevars.in`, `src/Makevars.win.in`, the framework sources under
#' `src/rzig/framework`, the package author's Zig source
#' `src/rzig/src/main.zig`, the generated `R/rzig-wrappers.R`, and a managed
#' block in `NAMESPACE`.
#'
#' @param path Path to the package root; the directory must contain a
#'   `DESCRIPTION` file.
#' @param overwrite Replace files previously managed by RZig.
#'
#' @return An object of class `rzig_scaffold`: a list with `path` (the
#'   normalized package root), `package`, `files` (the paths written,
#'   relative to the root) and `exports` (the [rzig_exports][scan_exports()]
#'   found in `main.zig`), invisibly.
#' @examples
#' package_path <- tempfile("rzig-example-", tmpdir = tempdir())
#' dir.create(package_path)
#' writeLines(c("Package: examplepkg", "Version: 0.0.1"),
#'   file.path(package_path, "DESCRIPTION"))
#' scaffold <- use_rzig(package_path)
#' scaffold
#' file.exists(file.path(package_path, "src", "rzig", "src", "main.zig"))
#' unlink(package_path, recursive = TRUE)
#' @export
use_rzig <- function(path, overwrite = FALSE) {
  if (length(overwrite) != 1L || is.na(overwrite)) {
    stop("`overwrite` must be TRUE or FALSE", call. = FALSE)
  }
  overwrite <- isTRUE(overwrite)
  package_info <- .rzig_package_info(path)
  path <- package_info$path
  package <- package_info$package

  zig_assets <- system.file("zig", package = "rzig")
  templates <- system.file("templates", package = "rzig")
  if (!nzchar(zig_assets) || !nzchar(templates)) {
    stop("the installed rzig package is missing its scaffold assets", call. = FALSE)
  }

  managed <- .rzig_managed_files
  conflicts <- managed[file.exists(file.path(path, managed))]
  if (length(conflicts) && !overwrite) {
    stop(
      "RZig-managed files already exist; rerun with `overwrite = TRUE`: ",
      paste(conflicts, collapse = ", "),
      call. = FALSE
    )
  }

  if (overwrite) {
    unlink(file.path(path, "src", "rzig"), recursive = TRUE, force = TRUE)
  }
  dir.create(file.path(path, "src"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(path, "R"), recursive = TRUE, showWarnings = FALSE)
  .rzig_copy_tree(zig_assets, file.path(path, "src", "rzig"))

  file.copy(
    file.path(templates, "Makevars"),
    file.path(path, "src", "Makevars.in"),
    overwrite = overwrite,
    copy.mode = TRUE
  )
  file.copy(
    file.path(templates, "Makevars.win"),
    file.path(path, "src", "Makevars.win.in"),
    overwrite = overwrite,
    copy.mode = TRUE
  )
  for (script in c("configure", "configure.win", "cleanup", "cleanup.win")) {
    file.copy(
      file.path(templates, script),
      file.path(path, script),
      overwrite = overwrite,
      copy.mode = TRUE
    )
    Sys.chmod(file.path(path, script), mode = "0755")
  }

  entry <- readLines(file.path(templates, "entry.c"), warn = FALSE)
  entry <- gsub("@PKG@", gsub("[^A-Za-z0-9_]", "_", package), entry, fixed = TRUE)
  writeLines(entry, file.path(path, "src", "entry.c"), useBytes = TRUE)

  bindings <- document(path)

  written <- list.files(
    file.path(path, "src", "rzig"),
    recursive = TRUE,
    all.files = TRUE,
    no.. = TRUE
  )
  files <- c(
    "configure", "configure.win", "cleanup", "cleanup.win",
    file.path("src", "entry.c"),
    file.path("src", "Makevars.in"),
    file.path("src", "Makevars.win.in"),
    file.path("src", "rzig", written),
    file.path("R", "rzig-wrappers.R"),
    "NAMESPACE"
  )
  message("Created RZig scaffold in ", path)
  invisible(structure(
    list(
      path = path,
      package = package,
      files = unique(files),
      exports = bindings$exports
    ),
    class = "rzig_scaffold"
  ))
}

#' @export
print.rzig_scaffold <- function(x, ...) {
  cat(sprintf("RZig scaffold of package %s in %s\n", x$package, x$path))
  cat(sprintf("%d files written; the package author's Zig code lives in %s\n",
    length(x$files), file.path("src", "rzig", "src", "main.zig")))
  cat(sprintf("Exported Zig functions: %s\n",
    if (length(x$exports)) paste(vapply(x$exports, function(item) item$name, character(1L)), collapse = ", ") else "none"))
  cat("Next steps: edit main.zig, run document(), then install the package with a Zig compiler (see find_zig()).\n")
  invisible(x)
}
