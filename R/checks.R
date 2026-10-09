# Checks that run before compilation. Each check returns a list with
# `problems` (character; any entry makes the step fail) and `notes`
# (character; information that does not stop the build).

.rzig_check_result <- function(problems = character(), notes = character()) {
  list(problems = problems, notes = notes)
}

# ---------------------------------------------------------------------------
# Types of exported functions

.rzig_input_types <- c(
  "f64", "i32", "bool", "usize", "?f64", "?i32", "?bool", "?usize",
  "[]constf64", "[]consti32", "[]constbool", "[]constu8", "[]const[]constu8",
  "Matrix", "Sexp", "Mut([]f64)"
)

.rzig_vector_returns <- c(
  "[]f64", "[]constf64", "[]i32", "[]consti32", "[]bool", "[]constbool",
  "[][]constu8", "[]const[]constu8"
)

.rzig_plain_returns <- c(
  "void", "f64", "i32", "bool", .rzig_vector_returns, "[]constu8", "List", "Sexp"
)

.rzig_type_key <- function(type) {
  key <- gsub("[[:space:]]+", "", type, useBytes = TRUE)
  gsub("(^|[^A-Za-z0-9_])rzig\\.", "\\1", key, useBytes = TRUE)
}

.rzig_known_identifier <- function(identifier) {
  grepl(
    paste0(
      "^(f(16|32|64|80|128)|[iu][0-9]+|isize|usize|bool|void|anyopaque|",
      "anyerror|noreturn|type|anytype|comptime_int|comptime_float|const|",
      "c_[a-z]+|Matrix|Mut|Sexp|List|Attributed|Error|Ctx)$"
    ),
    identifier
  )
}

# "supported", "unsupported" or "local" (a name defined in the package
# author's source, which only the Zig compiler can resolve).
.rzig_classify <- function(key, supported) {
  if (key %in% supported) return("supported")
  spaced <- gsub("const", " const ", key, fixed = TRUE)
  identifiers <- regmatches(spaced, gregexpr("[A-Za-z_][A-Za-z0-9_]*", spaced))[[1L]]
  if (length(identifiers) && !all(.rzig_known_identifier(identifiers))) return("local")
  "unsupported"
}

.rzig_input_alternative <- function(key, type = key) {
  if (grepl("f(16|32|80|128)", key)) return(sub("f(16|32|80|128)", "f64", trimws(type)))
  if (grepl("^\\[\\]f64$", key)) return("rzig.Mut([]f64) to modify a duplicate, or []const f64 to read")
  if (grepl("[iu](8|16|64|128)|u32|isize", key) && !grepl("u8", key)) {
    return("i32, or f64 for integers beyond 32 bits")
  }
  "a supported type (see ?scan_exports)"
}

# Split "E!T" at the top-level "!" (outside brackets and parentheses).
.rzig_split_error_union <- function(key) {
  characters <- strsplit(key, "", fixed = TRUE)[[1L]]
  depth <- 0L
  for (index in seq_along(characters)) {
    character <- characters[[index]]
    if (character %in% c("(", "[", "{")) depth <- depth + 1L
    if (character %in% c(")", "]", "}")) depth <- depth - 1L
    if (character == "!" && depth == 0L) {
      return(c(
        error_set = substring(key, 1L, index - 1L),
        payload = substring(key, index + 1L)
      ))
    }
  }
  c(error_set = NA_character_, payload = key)
}

.rzig_classify_return <- function(key) {
  if (key %in% .rzig_plain_returns) return("supported")
  optional <- startsWith(key, "?")
  inner <- if (optional) substring(key, 2L) else key
  if (inner %in% .rzig_plain_returns) return("supported")
  attributed <- regmatches(inner, regexec("^Attributed\\((.*)\\)$", inner))[[1L]]
  if (length(attributed) == 2L) {
    return(if (attributed[[2L]] %in% .rzig_vector_returns) "supported" else
      .rzig_classify(attributed[[2L]], .rzig_vector_returns))
  }
  .rzig_classify(inner, .rzig_plain_returns)
}

.rzig_max_arguments <- 32L

.rzig_check_exports <- function(exports) {
  problems <- character()
  notes <- character()
  for (item in exports) {
    name <- item$name
    mutable <- 0L
    if (length(item$parameters) > .rzig_max_arguments) {
      problems <- c(problems, sprintf(
        "`%s` has %d R arguments; the maximum is %d",
        name, length(item$parameters), .rzig_max_arguments
      ))
    }
    for (position in seq_along(item$parameters)) {
      type <- item$parameter_types[[position]]
      key <- .rzig_type_key(type)
      argument <- item$parameters[[position]]
      if (key == "anytype") {
        problems <- c(problems, sprintf(
          "`%s`, argument `%s`: anytype cannot be exported; use a concrete supported type",
          name, argument
        ))
        next
      }
      if (key == "Mut([]f64)") mutable <- mutable + 1L
      verdict <- .rzig_classify(key, .rzig_input_types)
      if (verdict == "unsupported") {
        problems <- c(problems, sprintf(
          "`%s`, argument `%s`: type %s is not supported; use %s",
          name, argument, type, .rzig_input_alternative(key, type)
        ))
      } else if (verdict == "local") {
        notes <- c(notes, sprintf(
          "`%s`, argument `%s`: type %s is a name defined in the source; the compiler checks it",
          name, argument, type
        ))
      }
    }
    return_key <- .rzig_type_key(item$return_type)
    union <- .rzig_split_error_union(return_key)
    error_set <- union[["error_set"]]
    if (!is.na(error_set) && error_set != "Error") {
      if (error_set %in% c("", "anyerror") || startsWith(error_set, "error{")) {
        problems <- c(problems, sprintf(
          "`%s` returns %s; an exported function returns rzig.Error!T or T",
          name, item$return_type
        ))
      } else {
        notes <- c(notes, sprintf(
          "`%s`: error set %s is a name defined in the source; it must be rzig.Error",
          name, error_set
        ))
      }
    }
    payload <- union[["payload"]]
    verdict <- .rzig_classify_return(payload)
    if (verdict == "unsupported") {
      problems <- c(problems, sprintf(
        "`%s`: return type %s is not supported", name, item$return_type
      ))
    } else if (verdict == "local") {
      notes <- c(notes, sprintf(
        "`%s`: return type %s is a name defined in the source; the compiler checks it",
        name, item$return_type
      ))
    }
    if (mutable > 1L) {
      problems <- c(problems, sprintf(
        "`%s` has %d rzig.Mut([]f64) arguments; at most one is allowed", name, mutable
      ))
    }
    if (mutable == 1L && payload != "void") {
      problems <- c(problems, sprintf(
        "`%s` takes rzig.Mut([]f64) and must return void (or rzig.Error!void); the wrapper returns the duplicate",
        name
      ))
    }
  }
  .rzig_check_result(problems, notes)
}

# ---------------------------------------------------------------------------
# The package author's Zig source

.rzig_strip_line_comments <- function(lines) {
  sub("//.*$", "", lines, useBytes = TRUE)
}

.rzig_check_source <- function(path) {
  text <- .rzig_read_text(.rzig_source_path(path))
  lines <- .rzig_strip_line_comments(strsplit(.rzig_normalize_newlines(text), "\n", fixed = TRUE)[[1L]])
  code <- paste(lines, collapse = "\n")
  problems <- character()
  if (!grepl("rzig\\.registerModule\\([[:space:]]*@This\\(\\)[[:space:]]*\\)", code)) {
    problems <- c(problems, paste(
      "main.zig lacks `comptime { rzig.registerModule(@This()); }`;",
      "without it no native routine is generated and the package fails to load"
    ))
  }
  if (!grepl("pub[[:space:]]+const[[:space:]]+panic[[:space:]]*=", code) ||
      !grepl("rzig\\.Panic", code)) {
    problems <- c(problems, paste(
      "main.zig lacks `pub const panic = rzig.Panic;`;",
      "without it a failed safety check terminates the R session"
    ))
  }
  .rzig_check_result(problems)
}

# ---------------------------------------------------------------------------
# R code of the package

.rzig_check_r_conflicts <- function(path, exports) {
  files <- list.files(file.path(path, "R"), pattern = "\\.[RrSsq]$", full.names = TRUE)
  files <- files[basename(files) != "rzig-wrappers.R"]
  problems <- character()
  for (file in files) {
    lines <- readLines(file, warn = FALSE)
    for (item in exports) {
      pattern <- paste0(
        "^[[:space:]]*`?", gsub("([.\\\\|()\\[\\]{}^$*+?])", "\\\\\\1", item$name, perl = TRUE),
        "`?[[:space:]]*(<-|=)[[:space:]]*function"
      )
      if (any(grepl(pattern, lines, perl = TRUE))) {
        problems <- c(problems, sprintf(
          "`%s` is also defined in R/%s; R keeps whichever definition is collated last",
          item$name, basename(file)
        ))
      }
    }
  }
  .rzig_check_result(problems)
}

# ---------------------------------------------------------------------------
# Files managed by rzig

.rzig_template_pairs <- function(package) {
  templates <- system.file("templates", package = "rzig")
  list(
    list(file = "configure", template = file.path(templates, "configure")),
    list(file = "configure.win", template = file.path(templates, "configure.win")),
    list(file = "cleanup", template = file.path(templates, "cleanup")),
    list(file = "cleanup.win", template = file.path(templates, "cleanup.win")),
    list(file = file.path("src", "Makevars.in"), template = file.path(templates, "Makevars")),
    list(file = file.path("src", "Makevars.win.in"), template = file.path(templates, "Makevars.win"))
  )
}

.rzig_same_text <- function(a, b) {
  identical(.rzig_normalize_newlines(.rzig_read_text(a)), .rzig_normalize_newlines(.rzig_read_text(b)))
}

.rzig_check_scaffold <- function(path, package) {
  problems <- character()
  notes <- character()
  managed <- .rzig_managed_files
  present <- file.exists(file.path(path, managed))
  framework <- file.path(path, "src", "rzig", "framework", "rzig.zig")
  if (!all(present) || !file.exists(framework)) {
    missing <- c(managed[!present], if (!file.exists(framework)) file.path("src", "rzig", "framework"))
    return(.rzig_check_result(paste0(
      "missing: ", paste(missing, collapse = ", "), "; run use_rzig()"
    )))
  }
  assets <- system.file("zig", package = "rzig")
  shipped <- list.files(assets, recursive = TRUE, all.files = TRUE)
  shipped <- shipped[!grepl("^src/|^framework/generated/manifest\\.zig$", shipped)]
  outdated <- shipped[!vapply(shipped, function(file) {
    target <- file.path(path, "src", "rzig", file)
    file.exists(target) && .rzig_same_text(target, file.path(assets, file))
  }, logical(1L))]
  if (length(outdated)) {
    problems <- c(problems, sprintf(
      "%d framework file%s differ%s from rzig %s (%s); run use_rzig(path, overwrite = TRUE), which keeps src/rzig/src",
      length(outdated), if (length(outdated) == 1L) "" else "s",
      if (length(outdated) == 1L) "s" else "",
      as.character(utils::packageVersion("rzig")),
      paste(utils::head(outdated, 3L), collapse = ", ")
    ))
  }
  if (!is.null(package)) {
    customized <- character()
    for (pair in .rzig_template_pairs(package)) {
      if (!.rzig_same_text(file.path(path, pair$file), pair$template)) {
        customized <- c(customized, pair$file)
      }
    }
    if (length(customized)) {
      notes <- c(notes, paste0(
        "differs from the rzig template: ", paste(customized, collapse = ", ")
      ))
    }
  }
  if (.Platform$OS.type != "windows") {
    scripts <- c("configure", "cleanup")
    blocked <- scripts[file.access(file.path(path, scripts), mode = 1L) != 0L]
    if (length(blocked)) {
      problems <- c(problems, sprintf(
        "%s not executable; R then skips it and the Zig library is never built; run Sys.chmod(file.path(path, c(%s)), \"0755\")",
        paste(blocked, collapse = " and "),
        paste0("\"", blocked, "\"", collapse = ", ")
      ))
    }
  }
  .rzig_check_result(problems, notes)
}

# ---------------------------------------------------------------------------
# DESCRIPTION

.rzig_check_description <- function(path) {
  file <- file.path(path, "DESCRIPTION")
  if (!file.exists(file)) {
    return(.rzig_check_result("no DESCRIPTION file"))
  }
  fields <- tryCatch(read.dcf(file)[1L, ], error = function(error) NULL)
  if (is.null(fields) || !nzchar(fields[["Package"]] %||% "")) {
    return(.rzig_check_result("DESCRIPTION has no Package field"))
  }
  problems <- character()
  version <- fields[["Version"]] %||% ""
  if (is.na(package_version(version, strict = FALSE))) {
    problems <- c(problems, sprintf("Version \"%s\" is not a valid package version", version))
  }
  wanted <- c("Title", "Description", "License")
  missing <- wanted[!wanted %in% names(fields)]
  if (!any(c("Authors@R", "Maintainer") %in% names(fields))) missing <- c(missing, "Authors@R")
  notes <- if (length(missing)) {
    paste("R CMD check also requires", paste(missing, collapse = ", "))
  } else character()
  .rzig_check_result(problems, notes)
}

`%||%` <- function(x, y) if (is.null(x) || (length(x) == 1L && is.na(x))) y else x

# ---------------------------------------------------------------------------
# The C toolchain of R

.rzig_toolchain_cache <- new.env(parent = emptyenv())

.rzig_check_toolchain <- function() {
  if (!is.null(.rzig_toolchain_cache$result)) return(.rzig_toolchain_cache$result)
  problems <- character()
  notes <- character()
  r <- file.path(R.home("bin"), "R")
  configured <- tryCatch(
    suppressWarnings(system2(r, c("CMD", "config", "CC"), stdout = TRUE, stderr = TRUE)),
    error = function(error) character()
  )
  configured <- trimws(utils::tail(configured[nzchar(trimws(configured))], 1L))
  compiler <- if (length(configured)) strsplit(configured, "[[:space:]]+")[[1L]][[1L]] else ""
  located <- if (nzchar(compiler)) Sys.which(compiler)[[1L]] else ""
  if (!nzchar(located)) {
    problems <- c(problems, sprintf(
      "the C compiler of R (%s) is not on the PATH; install %s",
      if (nzchar(compiler)) compiler else "R CMD config CC",
      .rzig_toolchain_hint()
    ))
  } else {
    probe <- suppressWarnings(tryCatch(
      system2(located, "--version", stdout = TRUE, stderr = TRUE, timeout = 30),
      error = function(error) structure(conditionMessage(error), status = 1L)
    ))
    if (!is.null(attr(probe, "status"))) {
      problems <- c(problems, sprintf(
        "the C compiler %s does not run (%s); install %s",
        compiler, trimws(probe[1L]), .rzig_toolchain_hint()
      ))
    } else {
      notes <- c(notes, sprintf("C compiler %s", compiler))
    }
  }
  make <- Sys.getenv("MAKE", unset = "make")
  make <- strsplit(make, "[[:space:]]+")[[1L]][[1L]]
  if (!nzchar(Sys.which(make))) {
    problems <- c(problems, sprintf("`%s` is not on the PATH; install %s", make, .rzig_toolchain_hint()))
  }
  if (!file.exists(file.path(R.home("include"), "R.h"))) {
    problems <- c(problems, paste(
      "the R headers are missing; install the R development package",
      "(r-base-dev on Debian and Ubuntu, R-devel on Fedora)"
    ))
  }
  result <- .rzig_check_result(problems, notes)
  .rzig_toolchain_cache$result <- result
  result
}

.rzig_toolchain_hint <- function() {
  switch(
    Sys.info()[["sysname"]],
    Darwin = "the Xcode command line tools (xcode-select --install)",
    Windows = "Rtools (https://cran.r-project.org/bin/windows/Rtools/)",
    "a C compiler, make and the R development headers"
  )
}
