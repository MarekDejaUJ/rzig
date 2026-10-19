#' Share Zig modules between R packages
#'
#' A package can share Zig code with other packages as a Zig module: the file
#' `inst/zig/<module>/root.zig`, with the files it imports from that folder,
#' installed with the package. `use_rzig_import()` lets the Zig code of the
#' package at `path` use such a module with `@import("<module>")`: it adds
#' `<package>/<module>` to the field `Config/rzig/imports` of `DESCRIPTION`
#' and `<package>` to `LinkingTo`, so that R installs the providing package
#' first. `configure` finds the module in the installed package and passes it
#' to `zig build`; the module can import rzig and the other imported modules.
#' The module is compiled into the importing package, so nothing is linked
#' between the packages when they run.
#'
#' `use_rzig_module()` creates `inst/zig/<module>/root.zig` with a starter in
#' the providing package and, with `import = TRUE`, imports the module in the
#' package's own Zig code as well (an entry that names the package itself
#' refers to its source). It also writes `inst/include/<package>_rzig.h`, a
#' header without declarations: R CMD check expects a package in `LinkingTo`
#' to provide an `include` directory.
#'
#' @param path Path to the package root.
#' @param package The name of the package that provides the module.
#' @param module The name of the Zig module, a Zig identifier other than
#'   `rzig`, `std`, `builtin` and `root`.
#' @param import For `use_rzig_module()`: also import the module in the
#'   package's own Zig code.
#'
#' @return The path of `DESCRIPTION` (`use_rzig_import()`) or of the module's
#'   `root.zig` (`use_rzig_module()`), invisibly.
#' @examples
#' provider <- tempfile("rzig-provider-", tmpdir = tempdir())
#' dir.create(provider)
#' writeLines(c("Package: kernelpkg", "Version: 0.0.1"), file.path(provider, "DESCRIPTION"))
#' use_rzig_module(provider, "kernels")
#' consumer <- tempfile("rzig-consumer-", tmpdir = tempdir())
#' dir.create(consumer)
#' writeLines(c("Package: userpkg", "Version: 0.0.1"), file.path(consumer, "DESCRIPTION"))
#' use_rzig_import(consumer, "kernelpkg", "kernels")
#' read.dcf(file.path(consumer, "DESCRIPTION"), fields = c("LinkingTo", "Config/rzig/imports"))
#' unlink(c(provider, consumer), recursive = TRUE)
#' @export
use_rzig_import <- function(path, package, module) {
  info <- .rzig_package_info(path)
  if (!is.character(package) || length(package) != 1L || is.na(package) || !nzchar(package)) {
    stop("`package` must be one package name", call. = FALSE)
  }
  .rzig_check_module_name(module)
  .rzig_add_field_entry(info$path, .rzig_imports_field, paste0(package, "/", module))
  if (!identical(package, info$package)) .rzig_add_field_entry(info$path, "LinkingTo", package)
  message("Package ", info$package, " imports the Zig module ", module, " of package ", package)
  invisible(file.path(info$path, "DESCRIPTION"))
}

#' @rdname use_rzig_import
#' @export
use_rzig_module <- function(path, module, import = TRUE) {
  info <- .rzig_package_info(path)
  .rzig_check_module_name(module)
  if (!is.logical(import) || length(import) != 1L || is.na(import)) {
    stop("`import` must be TRUE or FALSE", call. = FALSE)
  }
  file <- file.path(info$path, "inst", "zig", module, "root.zig")
  if (!file.exists(file)) {
    dir.create(dirname(file), recursive = TRUE, showWarnings = FALSE)
    writeLines(c(
      sprintf("//! The Zig module `%s` of package %s. Other packages import it with", module, info$package),
      sprintf("//! rzig::use_rzig_import(path, \"%s\", \"%s\") and `@import(\"%s\")`.", info$package, module, module),
      "",
      "const std = @import(\"std\");",
      "",
      "/// The sum of `values`.",
      "pub fn sum(values: []const f64) f64 {",
      "    var total: f64 = 0;",
      "    for (values) |value| total += value;",
      "    return total;",
      "}",
      "",
      "test \"sum\" {",
      "    try std.testing.expectEqual(@as(f64, 6), sum(&.{ 1, 2, 3 }));",
      "}"
    ), file)
  }
  header <- file.path(info$path, "inst", "include", paste0(.rzig_c_identifier(info$package), "_rzig.h"))
  if (!file.exists(header)) {
    dir.create(dirname(header), recursive = TRUE, showWarnings = FALSE)
    writeLines(c(
      sprintf("/* Package %s provides Zig modules (inst/zig) to packages that list it in", info$package),
      " * LinkingTo and import a module in Config/rzig/imports (rzig::use_rzig_import()).",
      " * R CMD check expects a package in LinkingTo to provide this include folder;",
      " * the header declares no C interface. */"
    ), header)
  }
  if (import) .rzig_add_field_entry(info$path, .rzig_imports_field, paste0(info$package, "/", module))
  message("Package ", info$package, " provides the Zig module ", module, " in inst/zig/", module, "/root.zig")
  invisible(file)
}

.rzig_imports_field <- "Config/rzig/imports"

.rzig_check_module_name <- function(module) {
  if (!is.character(module) || length(module) != 1L || is.na(module) ||
      !grepl("^[A-Za-z_][A-Za-z0-9_]*$", module)) {
    stop("`module` must be a Zig identifier, for example \"kernels\"", call. = FALSE)
  }
  if (module %in% c("rzig", "std", "builtin", "root")) {
    stop("the Zig module name \"", module, "\" is reserved", call. = FALSE)
  }
  invisible(module)
}

# Add `entry` to a comma-separated field of DESCRIPTION unless it is there;
# entries of LinkingTo are compared by package name.
.rzig_add_field_entry <- function(path, field_name, entry) {
  file <- file.path(path, "DESCRIPTION")
  lines <- strsplit(.rzig_normalize_newlines(.rzig_read_text(file)), "\n", fixed = TRUE)[[1L]]
  field <- .rzig_description_field(lines, field_name)
  present <- if (identical(field_name, "LinkingTo")) sub("[[:space:](].*$", "", field$entries) else field$entries
  if (entry %in% present) return(invisible(FALSE))
  line <- paste0(field_name, ": ", paste(c(field$entries, entry), collapse = ", "))
  if (is.na(field$start)) {
    lines <- c(lines, line)
  } else {
    lines <- c(lines[seq_len(field$start - 1L)], line, lines[seq.int(field$end + 1L, length.out = length(lines) - field$end)])
  }
  .rzig_write_text(paste0(paste(lines, collapse = "\n"), "\n"), file)
  invisible(TRUE)
}

# The functions of inst/zig/tools/imports.R, which configure runs as well.
.rzig_imports_tool <- local({
  cached <- NULL
  function() {
    if (is.null(cached)) {
      script <- system.file("zig", "tools", "imports.R", package = "rzig")
      if (!nzchar(script)) stop("the installed rzig package is missing tools/imports.R", call. = FALSE)
      environment <- new.env(parent = baseenv())
      sys.source(script, envir = environment, keep.source = FALSE)
      cached <<- environment
    }
    cached
  }
})

# Problems of Config/rzig/imports: entries that do not resolve, and
# providing packages missing from LinkingTo.
.rzig_check_imports <- function(path) {
  file <- file.path(path, "DESCRIPTION")
  tool <- .rzig_imports_tool()
  entries <- tryCatch(tool$rzig_imports_entries(file), error = function(error) character())
  if (!length(entries)) return(character())
  problems <- character()
  resolved <- tryCatch(tool$rzig_imports_resolve(path), error = function(error) error)
  if (inherits(resolved, "error")) {
    problems <- c(problems, paste0("Config/rzig/imports: ", conditionMessage(resolved)))
  }
  fields <- read.dcf(file)[1L, ]
  own <- .rzig_field(fields, "Package") %||% ""
  linking <- trimws(strsplit(.rzig_field(fields, "LinkingTo") %||% "", ",", fixed = TRUE)[[1L]])
  linking <- sub("[[:space:](].*$", "", linking[nzchar(linking)])
  providers <- unique(sub("/.*$", "", entries))
  missing <- setdiff(providers, c(own, linking))
  if (length(missing)) {
    problems <- c(problems, paste0(
      "Config/rzig/imports names ", paste(missing, collapse = ", "), ", which LinkingTo does not list; ",
      "R then may install this package first"
    ))
  }
  installed <- setdiff(providers, own)
  installed <- installed[nzchar(vapply(installed, function(name) system.file(package = name), character(1L)))]
  no_include <- installed[!nzchar(vapply(installed, function(name) system.file("include", package = name), character(1L)))]
  if (length(no_include)) {
    problems <- c(problems, paste0(
      paste(no_include, collapse = ", "), " provides no include folder, which R CMD check expects of a ",
      "package in LinkingTo; rzig::use_rzig_module() in that package writes one"
    ))
  }
  if (!file.exists(file.path(path, "src", "rzig", "tools", "imports.R"))) {
    problems <- c(problems, "Config/rzig/imports needs src/rzig/tools/imports.R; run update_rzig(path)")
  }
  problems
}
