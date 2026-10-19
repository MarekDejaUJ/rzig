# Resolve the Zig modules that DESCRIPTION imports (Config/rzig/imports) to
# their root files: for configure, which passes them to `zig build` as
# -Drzig-imports, and for rzig::test_zig(). Base R only, because rzig need
# not be installed when a package created with it is installed.
#
# An entry "pkg/module" is inst/zig/<module>/root.zig of the installed
# package pkg (listed in LinkingTo, so that R installs it first), or of the
# source of this package when pkg is this package.

rzig_imports_reserved <- c("rzig", "std", "builtin", "root")

rzig_imports_entries <- function(description) {
  fields <- read.dcf(description)
  if (!"Config/rzig/imports" %in% colnames(fields)) return(character())
  value <- unname(fields[1L, "Config/rzig/imports"])
  if (is.na(value)) return(character())
  entries <- trimws(strsplit(value, ",", fixed = TRUE)[[1L]])
  entries[nzchar(entries)]
}

rzig_imports_resolve <- function(root = ".") {
  description <- file.path(root, "DESCRIPTION")
  own <- unname(read.dcf(description, fields = "Package")[1L, 1L])
  entries <- rzig_imports_entries(description)
  # Every entry is checked before any is looked up.
  modules <- character()
  packages <- character()
  for (entry in entries) {
    parts <- strsplit(entry, "/", fixed = TRUE)[[1L]]
    if (length(parts) != 2L || !nzchar(parts[[1L]]) || !grepl("^[A-Za-z_][A-Za-z0-9_]*$", parts[[2L]])) {
      stop("the entry '", entry, "' of Config/rzig/imports is not package/module ",
        "with a Zig identifier as the module name", call. = FALSE)
    }
    if (parts[[2L]] %in% rzig_imports_reserved) {
      stop("the Zig module name '", parts[[2L]], "' of Config/rzig/imports is reserved", call. = FALSE)
    }
    if (parts[[2L]] %in% modules) {
      stop("Config/rzig/imports names the module '", parts[[2L]], "' twice", call. = FALSE)
    }
    packages <- c(packages, parts[[1L]])
    modules <- c(modules, parts[[2L]])
  }
  resolved <- character()
  for (index in seq_along(modules)) {
    package <- packages[[index]]
    module <- modules[[index]]
    file <- if (identical(package, own)) {
      file.path(root, "inst", "zig", module, "root.zig")
    } else {
      system.file("zig", module, "root.zig", package = package)
    }
    if (!nzchar(file) || !file.exists(file)) {
      stop(if (identical(package, own)) {
        paste0("inst/zig/", module, "/root.zig does not exist")
      } else {
        paste0("package ", package, " is not installed, or it has no Zig module ", module,
          " (inst/zig/", module, "/root.zig)")
      }, call. = FALSE)
    }
    file <- normalizePath(file, winslash = "/", mustWork = TRUE)
    if (grepl("[;=\"$`\\\\]", file)) {
      stop("the path of the Zig module ", module, " contains a character that the build cannot pass: ",
        file, call. = FALSE)
    }
    resolved[[module]] <- file
  }
  resolved
}

# The value of -Drzig-imports: name=root;name=root.
rzig_imports_option <- function(root = ".") {
  resolved <- rzig_imports_resolve(root)
  if (!length(resolved)) return("")
  paste(paste0(names(resolved), "=", resolved), collapse = ";")
}

if (sys.nframe() == 0L) {
  invisible(tryCatch({
    cat(rzig_imports_option("."), "\n", sep = "")
  }, error = function(error) {
    message("rzig: ", conditionMessage(error))
    quit(save = "no", status = 1L)
  }))
}
