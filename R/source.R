#' Compile Zig code from the R prompt
#'
#' `zig_function()` compiles Zig source code into a small package in the
#' session's temporary directory and defines its exported functions in `env`,
#' the counterpart of `Rcpp::cppFunction()`. `zig_source()` does the same for
#' a file, and `zig_eval()` evaluates one Zig expression.
#'
#' The code is placed in a generated `main.zig` after the lines
#' `const std = @import("std");`, `const builtin = @import("builtin");`,
#' `const rzig = @import("rzig");` and the panic handler declaration (each
#' left out when the code declares it), and before the registration block.
#' Public functions marked `/// @export` are exported; when the code marks
#' none, every top-level `pub fn` is exported. The types, errors and checks of
#' the boundary are those of a package ([scan_exports()], [rzig_status()]).
#'
#' Builds are cached for the session by the code, the rzig version and the
#' Zig compiler: calling `zig_function()` again with the same code defines the
#' functions without compiling. A failed build is reported with the lines of
#' `code` and stops with an error.
#'
#' @param code Zig source code, a character vector whose elements are lines.
#' @param env The environment in which the functions are defined.
#' @param quiet If `FALSE`, print the build result.
#' @param file A Zig source file.
#' @param expr A Zig expression, as a string.
#' @param type The Zig type of the value of `expr`, a return type the
#'   boundary supports (for example `"f64"`, `"i32"`, `"bool"`,
#'   `"[]const u8"`).
#'
#' @return `zig_function()` and `zig_source()`: the function, if the code
#'   exports exactly one, otherwise a named list of the functions, invisibly.
#'   `zig_eval()`: the value of the expression.
#' @examples
#' \donttest{
#' if (isTRUE(find_zig(required = FALSE)$supported)) {
#'   twice <- zig_function("pub fn twice(x: f64) f64 { return 2 * x; }")
#'   twice(21)
#'   zig_eval("@sqrt(2.0)", type = "f64")
#' }
#' }
#' @export
zig_function <- function(code, env = parent.frame(), quiet = TRUE) {
  if (!is.character(code) || !length(code)) {
    stop("`code` must be a character vector of Zig source lines", call. = FALSE)
  }
  code <- unlist(strsplit(.rzig_normalize_newlines(paste(code, collapse = "\n")), "\n", fixed = TRUE))
  compiler <- find_zig()
  source <- .rzig_snippet_source(code)
  package <- paste0("rzigsrc", substr(.rzig_text_md5(paste(c(
    source$text, as.character(utils::packageVersion("rzig")), compiler$version
  ), collapse = "\n")), 1L, 12L))
  root <- file.path(tempdir(), "rzig-source")
  lib <- file.path(root, "lib")
  dir.create(lib, recursive = TRUE, showWarnings = FALSE)
  if (!package %in% loadedNamespaces()) {
    if (!dir.exists(file.path(lib, package))) {
      .rzig_build_snippet(package, root, lib, source, quiet)
    }
    loadNamespace(package, lib.loc = lib)
  }
  exports <- getNamespaceExports(package)
  names <- intersect(source$exports, exports)
  functions <- lapply(names, function(name) getExportedValue(package, name))
  names(functions) <- names
  for (name in names) assign(name, functions[[name]], envir = env)
  invisible(if (length(functions) == 1L) functions[[1L]] else functions)
}

#' @rdname zig_function
#' @export
zig_source <- function(file, env = parent.frame(), quiet = TRUE) {
  if (length(file) != 1L || !file.exists(file)) {
    stop("`file` must name an existing Zig source file", call. = FALSE)
  }
  zig_function(readLines(file, warn = FALSE), env = env, quiet = quiet)
}

#' @rdname zig_function
#' @export
zig_eval <- function(expr, type = "f64") {
  if (length(expr) != 1L || !is.character(expr)) {
    stop("`expr` must be one string holding a Zig expression", call. = FALSE)
  }
  if (length(type) != 1L || !is.character(type) || !nzchar(type)) {
    stop("`type` must name a Zig return type", call. = FALSE)
  }
  env <- new.env(parent = emptyenv())
  value <- zig_function(c(
    "/// @export",
    sprintf("pub fn rzig_eval_value() %s {", type),
    sprintf("    return %s;", expr),
    "}"
  ), env = env)
  value()
}

# The generated main.zig for a snippet: header lines the code does not declare
# itself, the code, the registration block; plus the names to export and the
# number of lines before the code.
.rzig_snippet_source <- function(code) {
  declares <- function(pattern) any(grepl(pattern, code, perl = TRUE))
  header <- c(
    if (!declares("^\\s*(pub\\s+)?const\\s+std\\s*=")) 'const std = @import("std");',
    if (!declares("^\\s*(pub\\s+)?const\\s+builtin\\s*=")) 'const builtin = @import("builtin");',
    if (!declares("^\\s*(pub\\s+)?const\\s+rzig\\s*=")) 'const rzig = @import("rzig");',
    if (!declares("^\\s*pub\\s+const\\s+panic\\s*=")) c(
      "pub const panic = if (builtin.is_test)",
      "    std.debug.FullPanic(std.debug.defaultPanic)",
      "else",
      "    rzig.Panic;"
    ),
    ""
  )
  marked <- .rzig_scan_text(paste(code, collapse = "\n"), "code")
  body <- code
  if (!length(marked)) {
    # Without markers, every top-level public function is exported.
    declaration <- "^pub\\s+((inline|export|extern)\\s+)?fn\\s+"
    starts <- grep(declaration, body, perl = TRUE)
    for (start in rev(starts)) body <- append(body, "/// @export", after = start - 1L)
    marked <- .rzig_scan_text(paste(body, collapse = "\n"), "code")
  }
  if (!length(marked)) {
    stop("the code defines no public function (`pub fn`) to export", call. = FALSE)
  }
  footer <- c("", "comptime {", "    rzig.registerModule(@This());", "}")
  list(
    text = c(header, body, footer),
    exports = vapply(Filter(function(item) !isTRUE(item$internal), marked), function(item) item$name, character(1L)),
    offset = length(header),
    inserted = length(body) - length(code)
  )
}

.rzig_build_snippet <- function(package, root, lib, source, quiet) {
  path <- file.path(root, package)
  unlink(path, recursive = TRUE)
  dir.create(path, recursive = TRUE)
  writeLines(c(
    paste("Package:", package), "Version: 0.0.1",
    "Title: Zig Code Compiled from the R Prompt",
    "Description: Generated by rzig::zig_function().", "License: GPL-3",
    "Authors@R: person('rzig', 'user', email = 'user@example.org', role = c('aut', 'cre'))"
  ), file.path(path, "DESCRIPTION"))
  suppressMessages(use_rzig(path))
  .rzig_write_text(paste0(paste(source$text, collapse = "\n"), "\n"),
    file.path(path, "src", "rzig", "src", "main.zig"))
  suppressMessages(document(path))
  result <- suppressWarnings(build_zig(path, lib = lib))
  if (!quiet || !result$ok) print(result)
  if (!result$ok) {
    lines <- .rzig_snippet_lines(result, source)
    stop("the Zig code did not compile", if (length(lines)) paste0(": ", paste(lines, collapse = "; ")),
      call. = FALSE)
  }
  invisible(result)
}

# Compiler errors located in the generated main.zig, as lines of the code.
.rzig_snippet_lines <- function(result, source) {
  errors <- result$errors
  if (!nrow(errors)) return(character())
  main <- file.path("src", "rzig", "src", "main.zig")
  vapply(seq_len(nrow(errors)), function(index) {
    message <- gsub("\n", " ", errors$message[[index]], fixed = TRUE)
    if (identical(errors$file[[index]], main) && !is.na(errors$line[[index]])) {
      line <- errors$line[[index]] - source$offset
      if (source$inserted == 0L && line >= 1L) return(sprintf("line %d of the code: %s", line, message))
    }
    if (!is.na(errors$function_name[[index]])) {
      return(sprintf("function %s: %s", errors$function_name[[index]], message))
    }
    message
  }, character(1L))
}

# ---------------------------------------------------------------------------
# knitr engine

#' A knitr engine for Zig chunks
#'
#' Compiles the code of a chunk with [zig_function()] and defines its exported
#' functions in the environment of the document, so later R chunks can call
#' them. rzig registers the engine as `zig` when knitr is loaded; to register
#' it explicitly, call `knitr::knit_engines$set(zig = rzig::eng_zig)`.
#'
#' @param options The chunk options knitr passes to an engine.
#' @return The chunk output for knitr.
#' @examples
#' # A document can use a chunk such as
#' #   ```{zig}
#' #   pub fn twice(x: f64) f64 { return 2 * x; }
#' #   ```
#' # after which R chunks call twice(). The engine is registered as "zig":
#' if (requireNamespace("knitr", quietly = TRUE)) {
#'   knitr::knit_engines$set(zig = eng_zig)
#'   is.function(knitr::knit_engines$get("zig"))
#' }
#' @export
eng_zig <- function(options) {
  code <- options$code
  out <- ""
  if (isTRUE(options$eval)) {
    env <- tryCatch(knitr::knit_global(), error = function(error) globalenv())
    zig_function(code, env = env)
    names <- .rzig_snippet_source(code)$exports
    out <- if (identical(options$results, "hide")) "" else
      sprintf("Defined from Zig: %s", paste0(names, "()", collapse = ", "))
  }
  knitr::engine_output(options, code, out)
}

.rzig_register_knitr_engine <- function(...) {
  if (isNamespaceLoaded("knitr")) {
    engines <- get("knit_engines", envir = asNamespace("knitr"))
    if (is.null(engines$get("zig"))) engines$set(zig = eng_zig)
  }
}
