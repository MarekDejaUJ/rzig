#' Generate R bindings from Zig exports
#'
#' Scans the Zig source of the package with [scan_exports()], renders the
#' bindings with [render_bindings()], and writes them: the Zig manifest
#' `src/rzig/framework/generated/manifest.zig`, the R wrappers
#' `R/rzig-wrappers.R`, and a managed block in `NAMESPACE`. Lines of
#' `NAMESPACE` outside the block, for example directives written by
#' roxygen2, are kept. The function is pure R; no Zig compiler is needed.
#'
#' Run `document()` after every change to an exported Zig signature or its
#' documentation comment, and before installing the package.
#'
#' @param path Path to a package previously initialized with [use_rzig()].
#'
#' @return The [rzig_bindings][render_bindings()] object that was written,
#'   with the element `files` naming the files written, invisibly.
#' @examples
#' package_path <- tempfile("rzig-document-", tmpdir = tempdir())
#' dir.create(package_path)
#' writeLines(c("Package: examplepkg", "Version: 0.0.1"),
#'   file.path(package_path, "DESCRIPTION"))
#' use_rzig(package_path)
#' bindings <- document(package_path)
#' bindings$files
#' cat(readLines(file.path(package_path, "NAMESPACE")), sep = "\n")
#' unlink(package_path, recursive = TRUE)
#' @export
document <- function(path) {
  info <- .rzig_package_info(path)
  manifest_path <- .rzig_manifest_path(info$path)
  if (!dir.exists(dirname(manifest_path))) {
    stop(
      "RZig scaffold not found; run `rzig::use_rzig()` first",
      call. = FALSE
    )
  }
  exports <- scan_exports(info$path)
  bindings <- render_bindings(exports, info$package)

  tryCatch(
    parse(text = bindings$wrappers, keep.source = FALSE),
    error = function(error) {
      stop("generated invalid R wrappers: ", conditionMessage(error), call. = FALSE)
    }
  )
  generated_namespace <- strsplit(bindings$namespace, "\n", fixed = TRUE)[[1L]]
  tryCatch(
    parse(text = generated_namespace, keep.source = FALSE),
    error = function(error) {
      stop("generated an invalid NAMESPACE block: ", conditionMessage(error), call. = FALSE)
    }
  )

  wrapper_path <- .rzig_wrapper_path(info$path)
  namespace_path <- file.path(info$path, "NAMESPACE")
  old_wrapper <- if (file.exists(wrapper_path)) {
    readLines(wrapper_path, warn = FALSE)
  } else {
    character()
  }
  existing_namespace <- if (file.exists(namespace_path)) {
    readLines(namespace_path, warn = FALSE)
  } else {
    character()
  }
  merged_namespace <- .rzig_merge_namespace(
    existing_namespace,
    generated_namespace,
    info$package,
    old_wrapper
  )

  .rzig_write_text(bindings$manifest, manifest_path)
  .rzig_write_text(bindings$wrappers, wrapper_path)
  .rzig_write_text(paste0(paste(merged_namespace, collapse = "\n"), "\n"), namespace_path)

  bindings$files <- c(
    file.path("src", "rzig", "framework", "generated", "manifest.zig"),
    file.path("R", "rzig-wrappers.R"),
    "NAMESPACE"
  )
  message(
    "Generated RZig bindings for ", info$package, ": ", length(exports),
    " exported function", if (length(exports) == 1L) "" else "s"
  )
  invisible(bindings)
}
