#' Update the rzig framework and build files of a package
#'
#' Brings a package created with [use_rzig()] to the installed version of
#' rzig without touching the package author's work:
#'
#' * the framework sources under `src/rzig/framework` are replaced by those of
#'   the installed rzig (the generated manifest is rewritten by [document()]);
#' * each build file (`configure`, `configure.win`, `cleanup`, `cleanup.win`,
#'   `src/Makevars.in`, `src/Makevars.win.in`, `src/entry.c`,
#'   `src/rzig/build.zig`, `src/rzig/build.zig.zon` and
#'   `src/rzig/tools/repack_macos_archive.sh`) is replaced only when it is
#'   identical to a template shipped by some version of rzig, that is, when the
#'   package author has not changed it. A changed (customized) build file is
#'   kept and listed, so that its differences from the new template can be
#'   reviewed; `force = TRUE` replaces it as well;
#' * missing build files are added, and the Zig scanner that rzig 0.2 copied
#'   into `src/rzig/tools/scan.zig` is removed;
#' * the package author's Zig sources in `src/rzig/src` and any file rzig does
#'   not know are never changed or removed;
#' * finally [document()] regenerates the bindings.
#'
#' @param path Path to a package previously initialized with [use_rzig()].
#' @param force If `TRUE`, also replace customized build files with the
#'   templates of the installed rzig.
#'
#' @return An object of class `rzig_update`: a list with `path`, `package`,
#'   `actions` (a data frame with the columns `file` and `action`, one of
#'   `"refreshed"`, `"updated"`, `"added"`, `"removed"`, `"kept"` (customized),
#'   `"replaced"` (customized, with `force = TRUE`) or `"current"`), `unknown`
#'   (files under `src/rzig/framework` that rzig does not ship) and `exports`,
#'   invisibly.
#' @examples
#' package_path <- tempfile("rzig-update-", tmpdir = tempdir())
#' dir.create(package_path)
#' writeLines(c("Package: examplepkg", "Version: 0.0.1"),
#'   file.path(package_path, "DESCRIPTION"))
#' use_rzig(package_path)
#' # A customized build file is kept.
#' cat("# package-specific setting\n",
#'   file = file.path(package_path, "src", "Makevars.in"), append = TRUE)
#' update_rzig(package_path)
#' unlink(package_path, recursive = TRUE)
#' @export
update_rzig <- function(path, force = FALSE) {
  if (length(force) != 1L || is.na(force)) {
    stop("`force` must be TRUE or FALSE", call. = FALSE)
  }
  info <- .rzig_package_info(path)
  path <- info$path
  if (!dir.exists(file.path(path, "src", "rzig", "framework"))) {
    stop("RZig scaffold not found; run `rzig::use_rzig()` first", call. = FALSE)
  }
  .rzig_guard_compiled_code(path)
  plan <- .rzig_refresh_plan(path, info$package)
  actions <- .rzig_refresh_apply(path, info$package, plan, force = isTRUE(force))
  .rzig_add_buildignore(path)
  .rzig_add_extra_sources(path)
  bindings <- document(path)
  result <- structure(
    list(
      path = path, package = info$package, actions = actions,
      unknown = attr(plan, "unknown"), exports = bindings$exports
    ),
    class = "rzig_update"
  )
  message(sprintf(
    "Updated RZig in package %s to rzig %s", info$package, as.character(utils::packageVersion("rzig"))
  ))
  invisible(result)
}

#' @export
print.rzig_update <- function(x, ...) {
  cat(sprintf("RZig update of package %s\n", x$package))
  labels <- c(
    refreshed = "framework sources refreshed", updated = "build files updated",
    added = "build files added", removed = "obsolete files removed",
    replaced = "customized build files replaced",
    kept = "customized build files kept (compare with the templates of rzig)"
  )
  for (action in names(labels)) {
    files <- x$actions$file[x$actions$action == action]
    if (length(files)) {
      cat(sprintf("  %s (%d):\n", labels[[action]], length(files)))
      for (file in files) cat("    ", file, "\n", sep = "")
    }
  }
  if (!nrow(x$actions[x$actions$action != "current", , drop = FALSE])) {
    cat("  everything matches the installed rzig\n")
  }
  if (length(x$unknown)) {
    cat("  files under src/rzig/framework that rzig does not ship (left in place):\n")
    for (file in x$unknown) cat("    ", file, "\n", sep = "")
  }
  invisible(x)
}

# ---------------------------------------------------------------------------
# Planning and applying a refresh

# The build files rzig writes, with the template each one comes from and the
# key of its historic hashes in .rzig_known_template_hashes.
.rzig_build_file_table <- function() {
  templates <- system.file("templates", package = "rzig")
  assets <- system.file("zig", package = "rzig")
  data.frame(
    file = c(
      "configure", "configure.win", "cleanup", "cleanup.win",
      file.path("src", "Makevars.in"), file.path("src", "Makevars.win.in"),
      file.path("src", "entry.c"),
      file.path("src", "rzig", "build.zig"), file.path("src", "rzig", "build.zig.zon"),
      file.path("src", "rzig", "tools", "repack_macos_archive.sh"),
      file.path("src", "rzig", "tools", "fetch_zig.R")
    ),
    template = c(
      file.path(templates, c("configure", "configure.win", "cleanup", "cleanup.win", "Makevars", "Makevars.win", "entry.c")),
      file.path(assets, c("build.zig", "build.zig.zon", file.path("tools", "repack_macos_archive.sh"),
        file.path("tools", "fetch_zig.R")))
    ),
    key = c(
      "configure", "configure.win", "cleanup", "cleanup.win", "Makevars", "Makevars.win", "entry.c",
      "build.zig", "build.zig.zon", "tools/repack_macos_archive.sh", "tools/fetch_zig.R"
    ),
    executable = c(TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, FALSE),
    stringsAsFactors = FALSE
  )
}

.rzig_normalized_text <- function(text) {
  text <- gsub("\r\n", "\n", text, fixed = TRUE)
  paste0(sub("\n+$", "", text), "\n")
}

.rzig_text_md5 <- function(text) {
  file <- tempfile("rzig-md5-")
  on.exit(unlink(file), add = TRUE)
  writeBin(charToRaw(.rzig_normalized_text(text)), file)
  unname(tools::md5sum(file))
}

# The text of a template as use_rzig() writes it into `package`.
.rzig_template_text <- function(template, key, package) {
  text <- .rzig_read_text(template)
  if (identical(key, "entry.c")) text <- gsub("@PKG@", .rzig_c_identifier(package), text, fixed = TRUE)
  text
}

# Whether a file of the package equals some template of some rzig version.
.rzig_is_known_template <- function(text, key, package) {
  if (identical(key, "entry.c")) {
    id <- .rzig_c_identifier(package)
    text <- gsub(paste0("R_init_", id), "R_init_@PKG@", text, fixed = TRUE)
    text <- gsub(paste0("R_unload_", id), "R_unload_@PKG@", text, fixed = TRUE)
  }
  .rzig_text_md5(text) %in% .rzig_known_template_hashes[[key]]
}

.rzig_refresh_plan <- function(path, package) {
  assets <- system.file("zig", package = "rzig")
  zig_dir <- file.path(path, "src", "rzig")
  shipped <- list.files(assets, recursive = TRUE, all.files = TRUE)
  framework <- shipped[startsWith(shipped, "framework/") & shipped != "framework/generated/manifest.zig"]
  rows <- list()
  add <- function(file, action, source = NA_character_, executable = FALSE) {
    rows[[length(rows) + 1L]] <<- data.frame(
      file = file, action = action, source = source, executable = executable,
      stringsAsFactors = FALSE
    )
  }
  for (file in framework) {
    target <- file.path(zig_dir, file)
    current <- file.exists(target) && .rzig_same_text(target, file.path(assets, file))
    add(file.path("src", "rzig", file), if (current) "current" else "refreshed", file.path(assets, file))
  }
  table <- .rzig_build_file_table()
  for (index in seq_len(nrow(table))) {
    entry <- table[index, ]
    target <- file.path(path, entry$file)
    if (!file.exists(target)) {
      add(entry$file, "added", entry$template, entry$executable)
      next
    }
    text <- .rzig_read_text(target)
    expected <- .rzig_template_text(entry$template, entry$key, package)
    action <- if (identical(.rzig_normalized_text(text), .rzig_normalized_text(expected))) {
      "current"
    } else if (.rzig_is_known_template(text, entry$key, package)) {
      "updated"
    } else {
      "kept"
    }
    add(entry$file, action, entry$template, entry$executable)
  }
  scanner <- file.path(zig_dir, "tools", "scan.zig")
  if (file.exists(scanner) && .rzig_is_known_template(.rzig_read_text(scanner), "tools/scan.zig", package)) {
    add(file.path("src", "rzig", "tools", "scan.zig"), "removed")
  }
  present <- list.files(file.path(zig_dir, "framework"), recursive = TRUE, all.files = TRUE)
  unknown <- setdiff(file.path("framework", present), c(framework, "framework/generated/manifest.zig"))
  plan <- do.call(rbind, rows)
  attr(plan, "unknown") <- if (length(unknown)) file.path("src", "rzig", unknown) else character()
  plan
}

.rzig_refresh_apply <- function(path, package, plan, force) {
  for (index in seq_len(nrow(plan))) {
    entry <- plan[index, ]
    action <- entry$action
    if (identical(action, "kept") && force) action <- plan$action[[index]] <- "replaced"
    target <- file.path(path, entry$file)
    if (action %in% c("refreshed", "updated", "added", "replaced")) {
      dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
      if (endsWith(entry$file, "entry.c")) {
        .rzig_write_text(.rzig_template_text(entry$source, "entry.c", package), target)
      } else if (!file.copy(entry$source, target, overwrite = TRUE, copy.mode = TRUE)) {
        stop("failed to update ", entry$file, call. = FALSE)
      }
      if (isTRUE(entry$executable)) Sys.chmod(target, mode = "0755")
    } else if (identical(action, "removed")) {
      unlink(target)
    }
  }
  plan[, c("file", "action")]
}

# use_rzig() and update_rzig() refuse to scaffold over compiled code the
# generated build would drop.
.rzig_guard_compiled_code <- function(path) {
  makevars <- .rzig_foreign_makevars(path)
  if (length(makevars)) {
    stop(
      paste(makevars, collapse = " and "), " exists. rzig writes src/Makevars and src/Makevars.win ",
      "from src/Makevars.in and src/Makevars.win.in during installation and removes them in ",
      "cleanup. Delete ", paste(makevars, collapse = " and "), ", run use_rzig() again, and move ",
      "its settings (for example PKG_LIBS) into src/Makevars.in and src/Makevars.win.in",
      call. = FALSE
    )
  }
  foreign <- .rzig_foreign_sources(path)
  if (length(foreign)) {
    stop(
      "src/ contains compiled sources that the rzig build does not compile: ",
      paste(foreign, collapse = ", "), ". The generated Makevars build the Zig sources and ",
      "src/entry.c only; keep those sources in another package, or port them to Zig",
      call. = FALSE
    )
  }
  invisible(TRUE)
}
