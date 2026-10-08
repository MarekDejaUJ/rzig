#' Scan the Zig source of a package for exported functions
#'
#' Reads `src/rzig/src/main.zig` and lists every public top-level Zig function
#' whose documentation comment contains a line `/// @export`. The scan is pure
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
#'   comment without the `@export` line) and `line` (the line of the
#'   declaration). The attributes `package`, `path` and `source` record the
#'   package name, its root and the scanned file. [as.data.frame()] turns the
#'   object into a table with one row per function.
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
  text <- .rzig_read_text(source_path)
  exports <- .rzig_scan_text(text, source_path)
  structure(
    exports,
    class = "rzig_exports",
    package = info$package,
    path = info$path,
    source = source_path
  )
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
    bodies <- .rzig_doc_bodies(doc_lines)
    marker <- trimws(bodies, whitespace = "[ \t\r]") == "@export"
    if (!any(marker)) {
      next
    }
    doc <- paste(bodies[!marker], collapse = "\n")

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

    exports[[length(exports) + 1L]] <- list(
      name = name,
      identifier = token,
      parameters = parameters,
      parameter_types = parameter_types,
      return_type = signature$return_type,
      doc = doc,
      line = index
    )
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
as.data.frame.rzig_exports <- function(x, ...) {
  if (!length(x)) {
    return(data.frame(
      name = character(),
      arguments = character(),
      return_type = character(),
      documented = logical(),
      line = integer(),
      stringsAsFactors = FALSE
    ))
  }
  data.frame(
    name = vapply(x, function(item) item$name, character(1L)),
    arguments = vapply(x, function(item) paste(item$parameters, collapse = ", "), character(1L)),
    return_type = vapply(x, function(item) item$return_type, character(1L)),
    documented = vapply(x, function(item) nzchar(item$doc), logical(1L)),
    line = vapply(x, function(item) as.integer(item$line), integer(1L)),
    stringsAsFactors = FALSE
  )
}

#' @export
print.rzig_exports <- function(x, ...) {
  source <- attr(x, "source", exact = TRUE)
  package <- attr(x, "package", exact = TRUE)
  cat(sprintf(
    "Zig exports of package %s (%s): %d function%s\n",
    package, if (is.null(source)) "main.zig" else source, length(x),
    if (length(x) == 1L) "" else "s"
  ))
  for (item in x) {
    cat("\n", item$name, "(", paste(item$parameters, collapse = ", "), ")\n", sep = "")
    mutable <- FALSE
    for (position in seq_along(item$parameters)) {
      type <- item$parameter_types[[position]]
      if (grepl("Mut\\(", type, useBytes = TRUE)) mutable <- TRUE
      cat(sprintf(
        "  %-14s %-26s %s\n", item$parameters[[position]], type,
        .rzig_describe_parameter(type)
      ))
    }
    cat(sprintf(
      "  %-14s %-26s %s\n", "returns", item$return_type,
      .rzig_describe_return(item$return_type, mutable)
    ))
  }
  invisible(x)
}

.rzig_describe_parameter <- function(type) {
  key <- gsub("[[:space:]]+", "", type, useBytes = TRUE)
  key <- sub("^rzig\\.", "", key, useBytes = TRUE)
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
    "[]constf64" = "double vector (borrowed, read-only)",
    "[]consti32" = "integer vector (borrowed, read-only)",
    "[]constbool" = "logical vector without NA (copied)",
    "[]constu8" = "character, length 1 (copied)",
    "[]const[]constu8" = "character vector without NA (copied)",
    "Matrix" = "double matrix (borrowed, read-only)",
    "Mut([]f64)" = "double vector (duplicated, writable)",
    "Sexp" = "any R object (borrowed)",
    "not supported; the Zig compiler rejects the signature"
  )
}

.rzig_describe_return <- function(type, mutable = FALSE) {
  key <- gsub("[[:space:]]+", "", type, useBytes = TRUE)
  key <- sub("^rzig\\.Error!", "", key, useBytes = TRUE)
  key <- sub("^rzig\\.", "", key, useBytes = TRUE)
  optional <- grepl("^\\?", key, useBytes = TRUE)
  if (optional) key <- substring(key, 2L)
  if (mutable && key == "void") {
    return("the writable duplicate of the mutable input (double vector)")
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
    "[]constu8" = "character, length 1",
    "[][]constu8" = , "[]const[]constu8" = "character vector",
    "List" = "named list",
    "Sexp" = "the supplied R object",
    "not supported; the Zig compiler rejects the signature"
  )
  if (optional) paste0(base, ", or NULL") else base
}
