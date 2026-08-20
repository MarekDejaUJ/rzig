#' Add RZig to an R package
#'
#' Creates a Zig source tree, portable build files, a generated native entry
#' stub, and a working `hello_zig()` example in an existing R package.
#'
#' @param path Path to the package root.
#' @param overwrite Replace files previously managed by RZig.
#'
#' @return The normalized package path, invisibly.
#' @export
use_rzig <- function(path = ".", overwrite = FALSE) {
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

  managed <- c(
    "configure",
    "configure.win",
    file.path("src", "entry.c"),
    file.path("src", "Makevars.in"),
    file.path("src", "Makevars.win.in"),
    file.path("src", "rzig"),
    file.path("R", "rzig-wrappers.R")
  )
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
  for (script in c("configure", "configure.win")) {
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

  document(path)

  message("Created RZig scaffold in ", path)
  invisible(path)
}

#' Generate R Bindings from Zig Exports
#'
#' Scans public Zig functions marked with `/// @export`, regenerates the Zig
#' manifest and R wrappers, and updates a managed block in `NAMESPACE`.
#'
#' @param path Path to a package previously initialized with [use_rzig()].
#'
#' @return The normalized package path, invisibly.
#' @export
document <- function(path = ".") {
  package_info <- .rzig_package_info(path)
  path <- package_info$path
  package <- package_info$package

  source_path <- file.path(path, "src", "rzig", "src", "main.zig")
  manifest_path <- file.path(
    path, "src", "rzig", "framework", "generated", "manifest.zig"
  )
  wrapper_path <- file.path(path, "R", "rzig-wrappers.R")
  namespace_path <- file.path(path, "NAMESPACE")
  if (!file.exists(source_path) || !dir.exists(dirname(manifest_path))) {
    stop(
      "RZig scaffold not found; run `rzig::use_rzig()` first",
      call. = FALSE
    )
  }

  scanner <- system.file("zig", "tools", "scan.zig", package = "rzig")
  if (!nzchar(scanner) || !file.exists(scanner)) {
    stop("the installed rzig package is missing its export scanner", call. = FALSE)
  }
  zig <- Sys.getenv("ZIG", unset = "")
  if (!nzchar(zig)) {
    zig <- unname(Sys.which("zig"))
  }
  if (!nzchar(zig)) {
    stop(
      "Zig was not found; install Zig 0.16.0 or set the ZIG environment variable",
      call. = FALSE
    )
  }

  generated <- tempfile("rzig-document-")
  dir.create(generated)
  on.exit(unlink(generated, recursive = TRUE, force = TRUE), add = TRUE)
  manifest_generated <- file.path(generated, "manifest.zig")
  wrapper_generated <- file.path(generated, "rzig-wrappers.R")
  namespace_generated <- file.path(generated, "NAMESPACE")

  .rzig_system2(
    zig,
    c(
      "run", "-O", "ReleaseSafe", shQuote(scanner), "--",
      shQuote(source_path), shQuote(manifest_generated),
      shQuote(wrapper_generated), shQuote(namespace_generated),
      shQuote(package)
    ),
    "scan Zig exports"
  )
  .rzig_system2(
    zig,
    c("fmt", shQuote(manifest_generated)),
    "format the generated Zig manifest"
  )

  tryCatch(
    parse(file = wrapper_generated, keep.source = FALSE),
    error = function(error) {
      stop("generated invalid R wrappers: ", conditionMessage(error), call. = FALSE)
    }
  )
  generated_namespace <- readLines(namespace_generated, warn = FALSE)
  tryCatch(
    parse(text = generated_namespace, keep.source = FALSE),
    error = function(error) {
      stop("generated an invalid NAMESPACE block: ", conditionMessage(error), call. = FALSE)
    }
  )

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
    package,
    old_wrapper
  )
  namespace_merged <- file.path(generated, "NAMESPACE-merged")
  writeLines(merged_namespace, namespace_merged, useBytes = TRUE)

  .rzig_replace_file(manifest_generated, manifest_path)
  .rzig_replace_file(wrapper_generated, wrapper_path)
  .rzig_replace_file(namespace_merged, namespace_path)

  message("Generated RZig bindings for ", package)
  invisible(path)
}

.rzig_package_info <- function(path) {
  if (length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("`path` must be one non-empty path", call. = FALSE)
  }
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  description_path <- file.path(path, "DESCRIPTION")
  if (!file.exists(description_path)) {
    stop("`path` must contain an R package DESCRIPTION file", call. = FALSE)
  }
  description <- read.dcf(description_path)
  if (!"Package" %in% colnames(description)) {
    stop("DESCRIPTION must declare a Package field", call. = FALSE)
  }
  package <- unname(description[1L, "Package"])
  if (!grepl("^[A-Za-z][A-Za-z0-9.]*$", package)) {
    stop("unsupported R package name: ", package, call. = FALSE)
  }
  list(path = path, package = package)
}

.rzig_system2 <- function(command, arguments, action) {
  output <- suppressWarnings(system2(
    command,
    arguments,
    stdout = TRUE,
    stderr = TRUE
  ))
  status <- attr(output, "status", exact = TRUE)
  if (is.null(status)) {
    status <- 0L
  }
  if (!identical(as.integer(status), 0L)) {
    details <- paste(output, collapse = "\n")
    if (nzchar(details)) {
      details <- paste0(":\n", details)
    }
    stop("failed to ", action, details, call. = FALSE)
  }
  invisible(output)
}

.rzig_merge_namespace <- function(existing, generated, package, old_wrapper) {
  begin <- "# Generated by rzig::document(): begin"
  end <- "# Generated by rzig::document(): end"
  starts <- which(trimws(existing) == begin)
  ends <- which(trimws(existing) == end)
  if (length(starts) != length(ends) || length(starts) > 1L ||
      (length(starts) == 1L && ends < starts)) {
    stop("NAMESPACE contains an incomplete RZig-generated block", call. = FALSE)
  }

  if (length(starts) == 1L) {
    existing <- existing[-seq.int(starts, ends)]
  } else {
    legacy <- sprintf(
      "useDynLib(%s, .registration = TRUE, .fixes = \"C_\")",
      package
    )
    existing <- existing[trimws(existing) != legacy]

    wrapper_matches <- regexec(
      "^([A-Za-z.][A-Za-z0-9._]*)[[:space:]]*<-[[:space:]]*function\\(",
      old_wrapper
    )
    captures <- regmatches(old_wrapper, wrapper_matches)
    old_exports <- vapply(
      captures[lengths(captures) > 1L],
      function(match) match[2L],
      character(1L)
    )
    legacy_exports <- c(
      sprintf("export(%s)", old_exports),
      sprintf("export(\"%s\")", old_exports)
    )
    generated_exports <- generated[grepl("^export\\(", generated)]
    existing <- existing[
      !trimws(existing) %in% unique(c(legacy_exports, generated_exports))
    ]
  }

  while (length(existing) && !nzchar(existing[[length(existing)]])) {
    existing <- existing[-length(existing)]
  }
  if (length(existing)) {
    c(existing, "", generated)
  } else {
    generated
  }
}

.rzig_replace_file <- function(source, destination) {
  dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(source, destination, overwrite = TRUE, copy.mode = TRUE)) {
    stop("failed to update generated file: ", destination, call. = FALSE)
  }
  invisible(destination)
}

.rzig_copy_tree <- function(source, destination) {
  files <- list.files(
    source,
    all.files = TRUE,
    full.names = TRUE,
    recursive = TRUE,
    include.dirs = FALSE,
    no.. = TRUE
  )
  prefix_length <- nchar(source) + 2L
  relative <- substring(files, prefix_length)
  for (index in seq_along(files)) {
    target <- file.path(destination, relative[index])
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(files[index], target, overwrite = TRUE, copy.mode = TRUE)) {
      stop("failed to copy RZig asset: ", relative[index], call. = FALSE)
    }
  }
  invisible(destination)
}
