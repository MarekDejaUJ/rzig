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
#' `src/rzig/framework`, the list of vendored C libraries
#' `src/rzig/c_libraries.zon` (empty), the package author's Zig source
#' `src/rzig/src/main.zig`, the generated `R/rzig-wrappers.R`, and a managed
#' block in `NAMESPACE`. Entries for the Zig build caches are added to
#' `.Rbuildignore`, and the Zig sources are listed in the
#' `Config/build/extra-sources` field of `DESCRIPTION`, so that
#' `devtools::load_all()` recompiles the package after a change to a Zig file.
#'
#' @param path Path to the package root; the directory must contain a
#'   `DESCRIPTION` file.
#' @param overwrite Allow `use_rzig()` on a package that already has RZig
#'   files. The framework sources and every build file that still matches an
#'   rzig template are then replaced, as with [update_rzig()]; the package
#'   author's Zig sources in `src/rzig/src` and files rzig does not know are
#'   kept. A build file the package author changed stops the call unless
#'   `force = TRUE`. [update_rzig()] is the usual way to update a package: it
#'   keeps customized build files and lists them.
#' @param force With `overwrite = TRUE`, also replace customized build files
#'   with the templates.
#' @param mixed Build the C, C++ and Fortran sources of `src/` with R's
#'   compilers next to the Zig code; see [use_rzig_mixed()]. Without it,
#'   `use_rzig()` stops when `src/` contains such sources.
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
use_rzig <- function(path, overwrite = FALSE, force = FALSE, mixed = FALSE) {
  if (length(overwrite) != 1L || is.na(overwrite)) {
    stop("`overwrite` must be TRUE or FALSE", call. = FALSE)
  }
  if (length(force) != 1L || is.na(force)) {
    stop("`force` must be TRUE or FALSE", call. = FALSE)
  }
  if (!is.logical(mixed) || length(mixed) != 1L || is.na(mixed)) {
    stop("`mixed` must be TRUE or FALSE", call. = FALSE)
  }
  overwrite <- isTRUE(overwrite)
  package_info <- .rzig_package_info(path)
  path <- package_info$path
  package <- package_info$package
  if (mixed) .rzig_set_config_true(path, .rzig_mixed_field)

  zig_assets <- system.file("zig", package = "rzig")
  templates <- system.file("templates", package = "rzig")
  if (!nzchar(zig_assets) || !nzchar(templates)) {
    stop("the installed rzig package is missing its scaffold assets", call. = FALSE)
  }
  .rzig_guard_compiled_code(path)

  managed <- .rzig_managed_files
  conflicts <- managed[file.exists(file.path(path, managed))]
  if (length(conflicts) && !overwrite) {
    stop(
      "RZig-managed files already exist: ", paste(conflicts, collapse = ", "),
      ". Update them with update_rzig(path), or rerun with `overwrite = TRUE`",
      call. = FALSE
    )
  }

  dir.create(file.path(path, "src"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(path, "R"), recursive = TRUE, showWarnings = FALSE)
  if (dir.exists(file.path(path, "src", "rzig", "framework"))) {
    # An existing scaffold: refresh it without removing anything rzig does not
    # own. Customized build files stop the call (before any change) unless
    # force = TRUE.
    plan <- .rzig_refresh_plan(path, package)
    kept <- plan$file[plan$action == "kept"]
    if (length(kept) && !isTRUE(force)) {
      stop(
        "these build files differ from every rzig template: ", paste(kept, collapse = ", "),
        ". update_rzig(path) keeps them; use_rzig(path, overwrite = TRUE, force = TRUE) replaces them",
        call. = FALSE
      )
    }
    .rzig_refresh_apply(path, package, plan, force = TRUE)
    starter <- file.path(path, "src", "rzig", "src", "main.zig")
    if (!file.exists(starter)) {
      dir.create(dirname(starter), recursive = TRUE, showWarnings = FALSE)
      file.copy(file.path(zig_assets, "src", "main.zig"), starter)
    }
  } else {
    keep_source <- file.exists(file.path(path, "src", "rzig", "src", "main.zig"))
    keep_libraries <- file.exists(file.path(path, "src", "rzig", "c_libraries.zon"))
    skip <- c(if (keep_source) "^src/", if (keep_libraries) "^c_libraries\\.zon$")
    .rzig_copy_tree(
      zig_assets, file.path(path, "src", "rzig"),
      skip = if (length(skip)) paste(skip, collapse = "|") else NULL
    )
    for (pair in list(c("Makevars", "src/Makevars.in"), c("Makevars.win", "src/Makevars.win.in"))) {
      file.copy(file.path(templates, pair[[1L]]), file.path(path, pair[[2L]]),
        overwrite = TRUE, copy.mode = TRUE)
    }
    for (script in c("configure", "configure.win", "cleanup", "cleanup.win")) {
      file.copy(file.path(templates, script), file.path(path, script),
        overwrite = TRUE, copy.mode = TRUE)
      Sys.chmod(file.path(path, script), mode = "0755")
    }
    entry <- readLines(file.path(templates, "entry.c"), warn = FALSE)
    entry <- gsub("@PKG@", .rzig_c_identifier(package), entry, fixed = TRUE)
    writeLines(entry, file.path(path, "src", "entry.c"), useBytes = TRUE)
  }
  .rzig_add_buildignore(path)
  description_changed <- .rzig_add_extra_sources(path)

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
    "NAMESPACE",
    ".Rbuildignore",
    if (description_changed) "DESCRIPTION"
  )
  message("Created RZig scaffold for package ", package)
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
  cat(sprintf("RZig scaffold of package %s: %d files written\n", x$package, length(x$files)))
  cat(sprintf("Zig source: %s\n", file.path("src", "rzig", "src", "main.zig")))
  cat(sprintf("Exported functions: %s\n",
    if (length(x$exports)) paste(vapply(x$exports, function(item) item$name, character(1L)), collapse = ", ") else "none"))
  cat("Next steps: edit main.zig, run document(), then install the package",
    "with a Zig compiler (see find_zig()).\n")
  invisible(x)
}
