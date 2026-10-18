#' Scan the Zig source of a package for exported functions
#'
#' Reads `src/rzig/src/main.zig`, and every Zig file that it imports with
#' `pub const name = @import("file.zig");` (recursively), and lists every
#' public top-level Zig function whose documentation comment contains a line
#' `/// @export`. A function of an imported file is registered as
#' `name.function`; its R name is the function name. `/// @export` above
#' `pub const twice = other.twice;` re-exports a function of a file imported as
#' `other` under the name `twice`. A file imported with a plain `const` cannot
#' be reached by the generated registration, so a marker in it is an error; a
#' marked file that is not imported at all is ignored, and [rzig_status()]
#' notes it. R names must be unique across all files.
#'
#' The marker line takes options: `/// @export internal` registers the function
#' without exporting its R wrapper, `/// @export invisible` makes the wrapper
#' return its value invisibly, and `/// @export name=<R name>` gives the wrapper
#' an R name other than the Zig name. Lines `/// @default <argument> <R
#' expression>` give default arguments of the wrapper, for example
#' `/// @default tolerance 1e-8`. A line
#' `/// @export internal` registers the function and generates its R wrapper
#' without exporting the wrapper from the package, for native routines that the
#' package's own R code calls. The scan is pure
#' R and needs no Zig compiler; the Zig compiler checks the parameter and
#' return types when the package is installed.
#'
#' A function is found when its declaration starts at the beginning of a line
#' with `pub fn` and the lines directly above it are `///` documentation
#' comments (blank lines and ordinary `//` comments between the comment block
#' and the declaration are ignored). The first parameter is omitted from the
#' R signature when its type is `*rzig.Ctx`.
#'
#' @param path Path to a package previously initialized with [use_rzig()].
#'
#' @return An object of class `rzig_exports`: a list with one element per
#'   exported function, each a list with `name` (the R function name),
#'   `identifier` (the Zig identifier as written), `parameters` (the R
#'   argument names), `parameter_types` (the Zig types of the R arguments),
#'   `return_type` (the Zig return type as written), `doc` (the documentation
#'   comment without the `@export` line), `line` (the line of the
#'   declaration), `internal` (`TRUE` for `/// @export internal`) and `file`
#'   (the file below `src/rzig/src`), `invisible` and `defaults` (a named
#'   character vector of R expressions). The attributes `package`, `path`,
#'   `source` (the entry file), `files` (every file scanned) and `unreachable`
#'   (marked files that `main.zig` does not import) record where the exports
#'   come from. [as.data.frame()] turns the object into a
#'   table with one row per function.
#' @examples
#' package_path <- tempfile("rzig-scan-", tmpdir = tempdir())
#' dir.create(package_path)
#' writeLines(c("Package: examplepkg", "Version: 0.0.1"),
#'   file.path(package_path, "DESCRIPTION"))
#' use_rzig(package_path)
#' exports <- scan_exports(package_path)
#' exports
#' as.data.frame(exports)
#' unlink(package_path, recursive = TRUE)
#' @export
scan_exports <- function(path) {
  info <- .rzig_package_info(path)
  source_path <- .rzig_source_path(info$path)
  if (!file.exists(source_path)) {
    stop(
      "RZig scaffold not found; run `rzig::use_rzig()` first",
      call. = FALSE
    )
  }
  scanned <- .rzig_scan_package(info$path)
  structure(
    scanned$exports,
    class = "rzig_exports",
    package = info$package,
    path = info$path,
    source = file.path("src", "rzig", "src", "main.zig"),
    files = scanned$files,
    unreachable = scanned$unreachable
  )
}

# ---------------------------------------------------------------------------
# Several files: main.zig and the files it imports publicly

.rzig_import_pattern <- paste0(
  "^(pub[[:space:]]+)?const[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*",
  "@import\\(\"([^\"]+\\.zig)\"\\)[[:space:]]*;"
)

.rzig_alias_pattern <- paste0(
  "^pub[[:space:]]+const[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*",
  "([A-Za-z_][A-Za-z0-9_]*)\\.([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*;"
)

.rzig_lines <- function(text) {
  text <- .rzig_normalize_newlines(text)
  lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
  if (length(lines) && grepl("\n$", text)) lines <- c(lines, "")
  lines
}

.rzig_scan_imports <- function(lines) {
  out <- list()
  for (index in seq_along(lines)) {
    match <- regmatches(lines[[index]], regexec(.rzig_import_pattern, lines[[index]]))[[1L]]
    if (length(match) == 4L) {
      out[[length(out) + 1L]] <- list(public = nzchar(match[[2L]]), alias = match[[3L]],
        file = match[[4L]], line = index)
    }
  }
  out
}

# The marker options of a doc block: NULL without @export, else "" or
# "internal"; anything else is an error.
.rzig_marker <- function(bodies, source_path, index) {
  trimmed <- trimws(bodies, whitespace = "[ \t\r]")
  marker <- grepl("^@export([[:space:]]|$)", trimmed)
  if (!any(marker)) return(NULL)
  if (sum(marker) > 1L) {
    stop(sprintf("%s:%d: more than one `/// @export` line above one function", source_path, index),
      call. = FALSE)
  }
  where <- sprintf("%s:%d", source_path, index)
  tokens <- strsplit(trimws(sub("^@export", "", trimmed[marker])), "[[:space:]]+")[[1L]]
  tokens <- tokens[nzchar(tokens)]
  name <- NULL
  for (token in tokens) {
    if (token %in% c("internal", "invisible")) next
    if (startsWith(token, "name=")) {
      name <- substring(token, 6L)
      if (!.rzig_is_syntactic(name) || name %in% .rzig_reserved_words) {
        stop(sprintf("%s: `%s` is not a syntactic R name for name=", where, name), call. = FALSE)
      }
      next
    }
    stop(sprintf(paste0(
      "%s: unknown option `%s` after @export; the options are `internal`, `invisible` ",
      "and `name=<R name>`"
    ), where, token), call. = FALSE)
  }
  # `@default <argument> <R expression>` lines give default arguments.
  default_lines <- grepl("^@default([[:space:]]|$)", trimmed)
  defaults <- character()
  for (line in trimmed[default_lines]) {
    parts <- regmatches(line, regexec("^@default[[:space:]]+([^[:space:]]+)[[:space:]]+(.+)$", line))[[1L]]
    if (length(parts) != 3L) {
      stop(sprintf("%s: write a default as `/// @default <argument> <R expression>`", where), call. = FALSE)
    }
    expression <- trimws(parts[[3L]])
    parsed <- tryCatch(parse(text = expression, keep.source = FALSE), error = function(error) NULL)
    if (is.null(parsed) || length(parsed) != 1L) {
      stop(sprintf("%s: the default of `%s` is not one R expression: %s", where, parts[[2L]], expression),
        call. = FALSE)
    }
    defaults[[parts[[2L]]]] <- expression
  }
  list(
    internal = "internal" %in% tokens,
    invisible = "invisible" %in% tokens,
    name = name,
    defaults = defaults,
    doc = paste(bodies[!marker & !default_lines], collapse = "\n")
  )
}

# Apply the marker options to an export record and check the defaults.
.rzig_apply_marker <- function(record, marker, source_path, index) {
  record$internal <- marker$internal
  record$invisible <- marker$invisible
  if (!is.null(marker$name)) record$name <- marker$name
  unknown <- setdiff(names(marker$defaults), record$parameters)
  if (length(unknown)) {
    stop(sprintf("%s:%d: @default names `%s`, which is not an argument of `%s`",
      source_path, index, unknown[[1L]], record$name), call. = FALSE)
  }
  record$defaults <- marker$defaults
  record
}

# The signature of the public function `name` declared in `lines`.
.rzig_find_function <- function(lines, name, source_path) {
  pattern <- paste0("^pub[[:space:]]+((inline|export|extern)[[:space:]]+)?fn[[:space:]]+", name, "[[:space:]]*\\(")
  index <- grep(pattern, lines, perl = TRUE)
  if (!length(index)) return(NULL)
  index <- index[[1L]]
  line <- lines[[index]]
  open <- regexpr("\\(", line, useBytes = TRUE)
  signature <- .rzig_signature(paste(lines[index:length(lines)], collapse = "\n"), open, name, source_path, index)
  list(signature = signature, line = index)
}

# Turn a parsed signature into the parameter fields of an export record.
.rzig_parameter_fields <- function(signature, name) {
  parameters <- character()
  parameter_types <- character()
  for (position in seq_along(signature$parameters)) {
    parameter <- .rzig_parameter(signature$parameters[[position]], name, position)
    type_key <- gsub("[[:space:]]+", "", parameter$type, useBytes = TRUE)
    if (position == 1L && type_key %in% c("*Ctx", "*rzig.Ctx")) next
    parameters <- c(parameters, .rzig_identifier_name(parameter$token))
    parameter_types <- c(parameter_types, parameter$type)
  }
  list(parameters = parameters, parameter_types = parameter_types)
}

.rzig_scan_package <- function(path) {
  root <- normalizePath(file.path(path, "src", "rzig", "src"), winslash = "/", mustWork = TRUE)
  main <- file.path(root, "main.zig")
  relative <- function(file) substring(file, nchar(root) + 2L)
  display <- function(file) file.path("src", "rzig", "src", relative(file))
  exports <- list()
  visited <- main
  visit <- function(file, prefix) {
    lines <- .rzig_lines(.rzig_read_text(file))
    found <- .rzig_scan_text(paste(lines, collapse = "\n"), display(file))
    for (item in found) {
      item$file <- relative(file)
      if (nzchar(prefix)) item$identifier <- paste0(prefix, ".", item$identifier)
      exports[[length(exports) + 1L]] <<- item
    }
    imports <- .rzig_scan_imports(lines)
    targets <- list()
    for (import in imports) {
      target <- normalizePath(file.path(dirname(file), import$file), winslash = "/", mustWork = FALSE)
      if (!file.exists(target) || !startsWith(target, paste0(root, "/"))) next
      targets[[import$alias]] <- target
      if (target %in% visited) next
      visited <<- c(visited, target)
      if (import$public) {
        visit(target, if (nzchar(prefix)) paste0(prefix, ".", import$alias) else import$alias)
      } else {
        marked <- .rzig_scan_text(.rzig_read_text(target), display(target))
        if (length(marked)) {
          stop(sprintf(paste0(
            "%s:%d: `%s` is marked `/// @export`, but %s imports %s with `const %s`, which the ",
            "generated registration cannot reach; write `pub const %s = @import(\"%s\");`"
          ), display(target), marked[[1L]]$line, marked[[1L]]$name, relative(file), import$file,
          import$alias, import$alias, import$file), call. = FALSE)
        }
      }
    }
    # `/// @export` above `pub const name = alias.function;` re-exports a
    # function of an imported file under `name`.
    for (index in seq_along(lines)) {
      match <- regmatches(lines[[index]], regexec(.rzig_alias_pattern, lines[[index]]))[[1L]]
      if (length(match) != 4L) next
      doc_lines <- .rzig_doc_block(lines, index)
      if (is.null(doc_lines)) next
      marker <- .rzig_marker(.rzig_doc_bodies(doc_lines), display(file), index)
      if (is.null(marker)) next
      name <- match[[2L]]
      target <- targets[[match[[3L]]]]
      found <- if (is.null(target)) NULL else
        .rzig_find_function(.rzig_lines(.rzig_read_text(target)), match[[4L]], display(target))
      if (is.null(found)) {
        stop(sprintf(
          "%s:%d: `%s` re-exports `%s.%s`, but no public function `%s` was found in a file imported as `%s`",
          display(file), index, name, match[[3L]], match[[4L]], match[[4L]], match[[3L]]
        ), call. = FALSE)
      }
      fields <- .rzig_parameter_fields(found$signature, name)
      record <- .rzig_apply_marker(list(
        name = name,
        identifier = if (nzchar(prefix)) paste0(prefix, ".", name) else name,
        parameters = fields$parameters,
        parameter_types = fields$parameter_types,
        return_type = found$signature$return_type,
        doc = marker$doc,
        line = index
      ), marker, display(file), index)
      record$file <- relative(file)
      exports[[length(exports) + 1L]] <<- record
    }
  }
  visit(main, "")
  names <- vapply(exports, function(item) item$name, character(1L))
  duplicated_names <- unique(names[duplicated(names)])
  if (length(duplicated_names)) {
    where <- vapply(exports[names == duplicated_names[[1L]]], function(item) {
      sprintf("%s:%d", item$file, item$line)
    }, character(1L))
    stop(sprintf("`%s` is exported more than once (%s)", duplicated_names[[1L]],
      paste(where, collapse = ", ")), call. = FALSE)
  }
  all_files <- normalizePath(list.files(root, pattern = "\\.zig$", recursive = TRUE, full.names = TRUE),
    winslash = "/")
  unreachable <- character()
  for (file in setdiff(all_files, visited)) {
    marked <- tryCatch(.rzig_scan_text(.rzig_read_text(file), display(file)), error = function(error) list())
    if (length(marked)) unreachable <- c(unreachable, relative(file))
  }
  list(exports = exports, files = relative(visited), unreachable = unreachable)
}

.rzig_scan_text <- function(text, source_path = "main.zig") {
  text <- .rzig_normalize_newlines(text)
  lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
  if (length(lines) && grepl("\n$", text)) {
    lines <- c(lines, "")
  }
  declaration <- paste0(
    "^pub[[:space:]]+((inline|export|extern)[[:space:]]+)?fn[[:space:]]+",
    "(@\"([^\"\\\\]|\\\\.)*\"|[A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\\("
  )
  exports <- list()
  for (index in seq_along(lines)) {
    line <- lines[[index]]
    if (!grepl(declaration, line, perl = TRUE, useBytes = TRUE)) {
      next
    }
    doc_lines <- .rzig_doc_block(lines, index)
    if (is.null(doc_lines)) {
      next
    }
    marker <- .rzig_marker(.rzig_doc_bodies(doc_lines), source_path, index)
    if (is.null(marker)) {
      next
    }
    doc <- marker$doc

    token <- regmatches(
      line,
      regexpr("(@\"([^\"\\\\]|\\\\.)*\"|[A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\\(", line, perl = TRUE, useBytes = TRUE)
    )
    token <- sub("[[:space:]]*\\($", "", token, perl = TRUE, useBytes = TRUE)
    name <- .rzig_identifier_name(token)
    open <- regexpr("\\(", line, useBytes = TRUE)
    rest <- paste(lines[index:length(lines)], collapse = "\n")
    signature <- .rzig_signature(rest, open, name, source_path, index)

    parameters <- character()
    parameter_types <- character()
    for (position in seq_along(signature$parameters)) {
      parameter <- .rzig_parameter(signature$parameters[[position]], name, position)
      type_key <- gsub("[[:space:]]+", "", parameter$type, useBytes = TRUE)
      if (position == 1L && type_key %in% c("*Ctx", "*rzig.Ctx")) {
        next
      }
      parameters <- c(parameters, .rzig_identifier_name(parameter$token))
      parameter_types <- c(parameter_types, parameter$type)
    }

    exports[[length(exports) + 1L]] <- .rzig_apply_marker(list(
      name = name,
      identifier = token,
      parameters = parameters,
      parameter_types = parameter_types,
      return_type = signature$return_type,
      doc = doc,
      line = index
    ), marker, source_path, index)
  }
  exports
}

.rzig_doc_block <- function(lines, index) {
  doc_lines <- character()
  position <- index - 1L
  while (position >= 1L) {
    line <- lines[[position]]
    if (grepl("^///($|[^/])", line, perl = TRUE, useBytes = TRUE)) {
      doc_lines <- c(line, doc_lines)
    } else if (grepl("^[[:space:]]*$", line, useBytes = TRUE) ||
               grepl("^[[:space:]]*//($|[^!])", line, perl = TRUE, useBytes = TRUE)) {
      if (length(doc_lines) && grepl("^[[:space:]]*////", line, useBytes = TRUE)) {
        break
      }
    } else {
      break
    }
    position <- position - 1L
  }
  if (!length(doc_lines)) {
    return(NULL)
  }
  doc_lines
}

.rzig_doc_bodies <- function(doc_lines) {
  bodies <- substring(doc_lines, 4L)
  leading_space <- substring(bodies, 1L, 1L) == " "
  bodies[leading_space] <- substring(bodies[leading_space], 2L)
  bodies
}

.rzig_identifier_name <- function(token) {
  if (grepl("^@\"", token, useBytes = TRUE)) {
    return(.rzig_decode_zig_string(substring(token, 2L)))
  }
  token
}

.rzig_decode_zig_string <- function(literal) {
  chars <- strsplit(literal, "", fixed = TRUE)[[1L]]
  if (length(chars) < 2L || chars[[1L]] != "\"" || chars[[length(chars)]] != "\"") {
    stop("malformed Zig string literal: ", literal, call. = FALSE)
  }
  inner <- chars[seq.int(2L, length(chars) - 1L)]
  out <- character()
  position <- 1L
  while (position <= length(inner)) {
    char <- inner[[position]]
    if (char != "\\") {
      out <- c(out, char)
      position <- position + 1L
      next
    }
    if (position == length(inner)) {
      stop("malformed escape in Zig string literal: ", literal, call. = FALSE)
    }
    escape <- inner[[position + 1L]]
    if (escape %in% c("n", "r", "t", "\\", "'", "\"")) {
      out <- c(out, switch(escape, n = "\n", r = "\r", t = "\t", escape))
      position <- position + 2L
    } else if (escape == "x") {
      hex <- paste(inner[position + 2:3], collapse = "")
      if (!grepl("^[0-9A-Fa-f]{2}$", hex)) {
        stop("malformed \\x escape in Zig string literal: ", literal, call. = FALSE)
      }
      out <- c(out, rawToChar(as.raw(strtoi(hex, 16L))))
      position <- position + 4L
    } else if (escape == "u") {
      remaining <- paste(inner[seq.int(position + 2L, length(inner))], collapse = "")
      match <- regmatches(remaining, regexpr("^\\{[0-9A-Fa-f]+\\}", remaining))
      if (!length(match)) {
        stop("malformed \\u escape in Zig string literal: ", literal, call. = FALSE)
      }
      code <- strtoi(substring(match, 2L, nchar(match) - 1L), 16L)
      out <- c(out, enc2utf8(intToUtf8(code)))
      position <- position + 2L + nchar(match)
    } else {
      stop("unsupported escape in Zig string literal: ", literal, call. = FALSE)
    }
  }
  paste(out, collapse = "")
}

.rzig_signature <- function(text, open, name, source_path, line) {
  chars <- strsplit(text, "", fixed = TRUE)[[1L]]
  total <- length(chars)
  position <- open
  depth <- 0L
  collected <- character()
  parameters_text <- NULL
  return_text <- NULL

  while (position <= total) {
    char <- chars[[position]]
    if (char == "\"" || char == "'") {
      end <- .rzig_skip_literal(chars, position, char)
      collected <- c(collected, chars[position:end])
      position <- end + 1L
      next
    }
    if (char == "/" && position < total && chars[[position + 1L]] == "/") {
      while (position <= total && chars[[position]] != "\n") {
        position <- position + 1L
      }
      next
    }
    if (char == "\\" && position < total && chars[[position + 1L]] == "\\") {
      while (position <= total && chars[[position]] != "\n") {
        collected <- c(collected, chars[[position]])
        position <- position + 1L
      }
      next
    }
    if (char %in% c("(", "[", "{")) {
      if (is.null(parameters_text) || char != "{" || depth > 0L) {
        depth <- depth + 1L
      }
    }
    if (char %in% c(")", "]", "}")) {
      depth <- depth - 1L
    }
    if (is.null(parameters_text)) {
      if (char == ")" && depth == 0L) {
        parameters_text <- paste(collected[-1L], collapse = "")
        collected <- character()
        position <- position + 1L
        next
      }
    } else if (depth == 0L && (char == "{" || char == ";")) {
      return_text <- paste(collected, collapse = "")
      break
    }
    collected <- c(collected, char)
    position <- position + 1L
  }

  if (is.null(parameters_text) || is.null(return_text)) {
    stop(
      sprintf(
        "%s:%d: the declaration of `%s` could not be read; check the parentheses of the signature",
        source_path, line, name
      ),
      call. = FALSE
    )
  }
  list(
    parameters = .rzig_split_parameters(parameters_text),
    return_type = trimws(gsub("[[:space:]]+", " ", return_text, useBytes = TRUE))
  )
}

.rzig_skip_literal <- function(chars, start, quote) {
  position <- start + 1L
  total <- length(chars)
  while (position <= total) {
    char <- chars[[position]]
    if (char == "\\") {
      position <- position + 2L
      next
    }
    if (char == quote || char == "\n") {
      return(position)
    }
    position <- position + 1L
  }
  total
}

.rzig_split_parameters <- function(text) {
  chars <- strsplit(text, "", fixed = TRUE)[[1L]]
  pieces <- character()
  current <- character()
  depth <- 0L
  position <- 1L
  total <- length(chars)
  while (position <= total) {
    char <- chars[[position]]
    if (char == "\"" || char == "'") {
      end <- .rzig_skip_literal(chars, position, char)
      current <- c(current, chars[position:end])
      position <- end + 1L
      next
    }
    if (char %in% c("(", "[", "{")) depth <- depth + 1L
    if (char %in% c(")", "]", "}")) depth <- depth - 1L
    if (char == "," && depth == 0L) {
      pieces <- c(pieces, paste(current, collapse = ""))
      current <- character()
    } else {
      current <- c(current, char)
    }
    position <- position + 1L
  }
  pieces <- c(pieces, paste(current, collapse = ""))
  pieces <- trimws(pieces)
  pieces[nzchar(pieces)]
}

.rzig_parameter <- function(text, name, position) {
  pattern <- paste0(
    "^(?s)(noalias[[:space:]]+)?(comptime[[:space:]]+)?",
    "(@\"([^\"\\\\]|\\\\.)*\"|[A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:[[:space:]]*(.+)$"
  )
  match <- regmatches(text, regexec(pattern, text, perl = TRUE, useBytes = TRUE))[[1L]]
  if (length(match) != 6L) {
    stop(
      sprintf(
        "exported function `%s`: parameter %d must be written as `name: Type`; found `%s`",
        name, position, text
      ),
      call. = FALSE
    )
  }
  list(
    token = match[[4L]],
    type = trimws(gsub("[[:space:]]+", " ", match[[6L]], useBytes = TRUE))
  )
}

#' @export
`[.rzig_exports` <- function(x, i) {
  structure(
    unclass(x)[i],
    class = "rzig_exports",
    package = attr(x, "package", exact = TRUE),
    path = attr(x, "path", exact = TRUE),
    source = attr(x, "source", exact = TRUE)
  )
}

#' @export
as.data.frame.rzig_exports <- function(x, ...) {
  if (!length(x)) {
    return(data.frame(
      name = character(),
      arguments = character(),
      return_type = character(),
      documented = logical(),
      internal = logical(),
      line = integer(),
      stringsAsFactors = FALSE
    ))
  }
  data.frame(
    name = vapply(x, function(item) item$name, character(1L)),
    arguments = vapply(x, function(item) paste(item$parameters, collapse = ", "), character(1L)),
    return_type = vapply(x, function(item) item$return_type, character(1L)),
    documented = vapply(x, function(item) nzchar(item$doc), logical(1L)),
    internal = vapply(x, .rzig_is_internal, logical(1L)),
    line = vapply(x, function(item) as.integer(item$line), integer(1L)),
    stringsAsFactors = FALSE
  )
}

.rzig_is_internal <- function(item) isTRUE(item$internal)

#' @export
print.rzig_exports <- function(x, ...) {
  source <- attr(x, "source", exact = TRUE)
  package <- attr(x, "package", exact = TRUE)
  files <- attr(x, "files", exact = TRUE)
  where <- if (length(files) > 1L) {
    paste0("src/rzig/src: ", paste(files, collapse = ", "))
  } else if (is.null(source)) "main.zig" else source
  cat(sprintf(
    "Zig exports of package %s (%s): %d function%s\n",
    package, where, length(x), if (length(x) == 1L) "" else "s"
  ))
  for (item in x) {
    cat("\n", item$name, "(", paste(item$parameters, collapse = ", "), ")",
      if (!is.null(item$file) && !identical(item$file, "main.zig")) paste0("  [", item$file, "]"),
      if (.rzig_is_internal(item)) "  [internal: not exported from the package]", "\n", sep = "")
    mutable <- FALSE
    for (position in seq_along(item$parameters)) {
      type <- item$parameter_types[[position]]
      if (grepl("Mut\\(", type, useBytes = TRUE)) mutable <- type
      cat(sprintf(
        "  %-10s %-22s %s\n", item$parameters[[position]], type,
        .rzig_describe_parameter(type)
      ))
    }
    cat(sprintf(
      "  %-10s %-22s %s\n", "returns", item$return_type,
      .rzig_describe_return(item$return_type, mutable)
    ))
  }
  invisible(x)
}

.rzig_describe_parameter <- function(type) {
  key <- .rzig_type_key(type)
  scalar <- c(
    f64 = "double, length 1",
    i32 = "integer, length 1",
    bool = "logical, length 1",
    usize = "whole number, length 1"
  )
  if (key %in% names(scalar)) return(scalar[[key]])
  if (grepl("^\\?", key, useBytes = TRUE) && substring(key, 2L) %in% names(scalar)) {
    return(paste0(scalar[[substring(key, 2L)]], ", NA or NULL"))
  }
  switch(
    key,
    "[]constf64" = "double vector, borrowed",
    "[]consti32" = "integer vector, borrowed",
    "[]constbool" = "logical vector, copied",
    "[]constLogical" = "logical vector with NA, borrowed",
    "[]const?[]constu8" = "character vector with NA, copied",
    "?[]constu8" = "character, length 1, NA or NULL",
    "Complex" = "complex, length 1",
    "[]constComplex" = "complex vector, borrowed",
    "Raw" = "raw vector, borrowed",
    "[]constu8" = "character, length 1, copied",
    "[]const[]constu8" = "character vector, copied",
    "Matrix" = "double matrix, borrowed",
    "IntMatrix" = "integer matrix, borrowed",
    "BoolMatrix" = "logical matrix, copied",
    "Mut([]f64)" = "double vector, writable duplicate",
    "Mut([]i32)" = "integer vector, writable duplicate",
    "Mut(Matrix)" = "double matrix, writable duplicate",
    "Mut(IntMatrix)" = "integer matrix, writable duplicate",
    "Sexp" = "R object, borrowed",
    "not supported; the Zig compiler rejects the signature"
  )
}

.rzig_describe_return <- function(type, mutable = FALSE) {
  key <- sub("^Error!", "", .rzig_type_key(type), useBytes = TRUE)
  optional <- grepl("^\\?", key, useBytes = TRUE)
  if (optional) key <- substring(key, 2L)
  if (!isFALSE(mutable) && key == "void") {
    duplicate <- sub(", writable duplicate$", "", .rzig_describe_parameter(mutable))
    return(paste0("the writable duplicate, ", if (grepl("^[aeiou]", duplicate)) "an " else "a ", duplicate))
  }
  attributed <- regmatches(key, regexec("^Attributed\\((.*)\\)$", key))[[1L]]
  if (length(attributed) == 2L) {
    inner <- .rzig_describe_return(attributed[[2L]])
    return(paste0(inner, " with names, dim or class attributes"))
  }
  base <- switch(
    key,
    "void" = "NULL",
    "f64" = "double, length 1",
    "i32" = "integer, length 1",
    "bool" = "logical, length 1",
    "[]f64" = , "[]constf64" = "double vector",
    "[]i32" = , "[]consti32" = "integer vector",
    "[]bool" = , "[]constbool" = "logical vector",
    "[]Logical" = , "[]constLogical" = "logical vector with NA",
    "Complex" = "complex, length 1",
    "[]Complex" = , "[]constComplex" = "complex vector",
    "Raw" = "raw vector",
    "[]constu8" = "character, length 1",
    "[][]constu8" = , "[]const[]constu8" = "character vector",
    "[]?[]constu8" = , "[]const?[]constu8" = "character vector with NA",
    "List" = "named list",
    "Sexp" = "the supplied R object",
    "not supported; the Zig compiler rejects the signature"
  )
  if (optional) paste0(base, ", or NULL") else base
}
