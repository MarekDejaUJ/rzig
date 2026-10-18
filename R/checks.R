# Checks that run before compilation. Each check returns a list with
# `problems` (character; any entry makes the step fail) and `notes`
# (character; information that does not stop the build).

.rzig_check_result <- function(problems = character(), notes = character()) {
  list(problems = problems, notes = notes)
}

# ---------------------------------------------------------------------------
# Types of exported functions

.rzig_input_types <- c(
  "f64", "i32", "bool", "usize", "i64", "?f64", "?i32", "?bool", "?usize", "?i64", "[]consti64",
  "[]constf64", "[]consti32", "[]constbool", "[]constu8", "[]const[]constu8",
  "[]constLogical", "[]const?[]constu8", "?[]constu8", "Complex", "[]constComplex", "Raw", "Factor",
  "CscMatrix",
  "Matrix", "IntMatrix", "BoolMatrix", "Sexp", "Function",
  "Mut([]f64)", "Mut([]i32)", "Mut(Matrix)", "Mut(IntMatrix)"
)

.rzig_vector_returns <- c(
  "[]f64", "[]constf64", "[]i32", "[]consti32", "[]bool", "[]constbool",
  "[]Logical", "[]constLogical", "[][]constu8", "[]const[]constu8",
  "[]?[]constu8", "[]const?[]constu8", "[]Complex", "[]constComplex"
)

.rzig_plain_returns <- c(
  "void", "f64", "i32", "i64", "[]i64", "[]consti64", "bool", .rzig_vector_returns, "[]constu8", "Complex", "Raw",
  "Factor", "List", "Sexp", "Function"
)

# The prefix `rzig.` goes first: removing the spaces of "[]const rzig.Logical"
# first would join it to the word before it.
.rzig_type_key <- function(type) {
  key <- gsub("(^|[^A-Za-z0-9_])rzig\\.", "\\1", type, useBytes = TRUE)
  gsub("[[:space:]]+", "", key, useBytes = TRUE)
}

.rzig_known_identifier <- function(identifier) {
  grepl(
    paste0(
      "^(f(16|32|64|80|128)|[iu][0-9]+|isize|usize|bool|void|anyopaque|",
      "anyerror|noreturn|type|anytype|comptime_int|comptime_float|const|",
      "c_[a-z]+|Matrix|IntMatrix|BoolMatrix|CscMatrix|Logical|Complex|Raw|Record|DataFrame|Factor|External|Mut|",
      "Sexp|List|Function|",
      "Attributed|Error|Ctx)$"
    ),
    identifier
  )
}

# "supported", "unsupported" or "local" (a name defined in the package
# author's source, which only the Zig compiler can resolve).
.rzig_classify <- function(key, supported) {
  if (key %in% supported) return("supported")
  # The fields of a record are checked by the compiler, which knows the struct.
  if (grepl("^(Record|DataFrame|External)\\(.+\\)$", key)) return("supported")
  spaced <- gsub("const", " const ", key, fixed = TRUE)
  identifiers <- regmatches(spaced, gregexpr("[A-Za-z_][A-Za-z0-9_]*", spaced))[[1L]]
  if (length(identifiers) && !all(.rzig_known_identifier(identifiers))) return("local")
  "unsupported"
}

.rzig_input_alternative <- function(key, type = key) {
  if (grepl("f(16|32|80|128)", key)) return(sub("f(16|32|80|128)", "f64", trimws(type)))
  if (grepl("^\\[\\]f64$", key)) return("rzig.Mut([]f64) to modify a duplicate, or []const f64 to read")
  if (grepl("^\\[\\]i32$", key)) return("rzig.Mut([]i32) to modify a duplicate, or []const i32 to read")
  if (startsWith(key, "Mut(")) {
    return("rzig.Mut([]f64), rzig.Mut([]i32), rzig.Mut(rzig.Matrix) or rzig.Mut(rzig.IntMatrix)")
  }
  if (grepl("[iu](8|16|64|128)|u32|isize", key) && !grepl("u8", key)) {
    return("i32, i64 (a bit64::integer64 in R), or f64")
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
      if (startsWith(key, "Mut(")) mutable <- mutable + 1L
      # ?T accepts NULL for any input T other than rzig.Mut and optionals.
      inner <- sub("^\\?", "", key)
      verdict <- if (startsWith(key, "?") && !grepl("^(\\?|Mut\\()", inner) &&
        inner %in% .rzig_input_types) "supported" else .rzig_classify(key, .rzig_input_types)
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
        "`%s` has %d rzig.Mut arguments; at most one is allowed", name, mutable
      ))
    }
    if (mutable == 1L && payload != "void") {
      problems <- c(problems, sprintf(
        "`%s` takes an rzig.Mut argument and must return void (or rzig.Error!void); the wrapper returns the duplicate",
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

.rzig_masking_packages <- c("base", "stats", "utils", "methods", "graphics", "grDevices")

# Exported functions that mask a function of a base or recommended-attached
# package when the client package is attached. This is legitimate (a package
# may provide its own `log`), so it is reported as a note.
.rzig_check_masking <- function(exports) {
  notes <- character()
  for (item in exports) {
    if (.rzig_is_internal(item)) next
    for (package in .rzig_masking_packages) {
      names <- if (identical(package, "base")) {
        ls(baseenv(), all.names = TRUE)
      } else {
        tryCatch(getNamespaceExports(package), error = function(error) character())
      }
      if (item$name %in% names) {
        notes <- c(notes, sprintf(
          "`%s` masks %s::%s when the package is attached", item$name, package, item$name
        ))
        break
      }
    }
  }
  .rzig_check_result(notes = notes)
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
    list(file = file.path("src", "Makevars.win.in"), template = file.path(templates, "Makevars.win")),
    list(file = file.path("src", "entry.c"), template = file.path(templates, "entry.c"), package = package)
  )
}

# Compare a file with a template. With `package`, the template's @PKG@
# placeholder is replaced the way use_rzig() writes the file.
.rzig_same_text <- function(a, b, package = NULL) {
  expected <- .rzig_normalize_newlines(.rzig_read_text(b))
  if (!is.null(package) && !is.null(expected)) {
    expected <- gsub("@PKG@", .rzig_c_identifier(package), expected, fixed = TRUE)
  }
  identical(.rzig_normalize_newlines(.rzig_read_text(a)), expected)
}

.rzig_c_identifier <- function(package) {
  gsub("[^A-Za-z0-9_]", "_", package)
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
  # The framework sources must match the installed rzig: the R side of the
  # boundary (scan, wrappers, checks) assumes them. The build files around them
  # (build.zig, build.zig.zon, tools/*) are templates a package author may
  # extend, like configure and the Makevars, so a difference is only a note.
  assets <- system.file("zig", package = "rzig")
  shipped <- list.files(assets, recursive = TRUE, all.files = TRUE)
  framework_files <- shipped[startsWith(shipped, "framework/") &
    shipped != "framework/generated/manifest.zig"]
  zig_templates <- shipped[!startsWith(shipped, "framework/") & !startsWith(shipped, "src/")]
  # c_libraries.zon belongs to the package author once it exists.
  authored <- "c_libraries.zon"
  missing_framework <- framework_files[!file.exists(file.path(path, "src", "rzig", framework_files))]
  outdated <- setdiff(framework_files, missing_framework)
  outdated <- outdated[!vapply(outdated, function(file) {
    .rzig_same_text(file.path(path, "src", "rzig", file), file.path(assets, file))
  }, logical(1L))]
  missing_templates <- zig_templates[!file.exists(file.path(path, "src", "rzig", zig_templates))]
  # The Zig downloader runs only when RZIG_DOWNLOAD_ZIG asks for it.
  missing_optional <- intersect(missing_templates, c("tools/fetch_zig.R", "tools/imports.R"))
  missing_templates <- setdiff(missing_templates, missing_optional)
  if ("tools/fetch_zig.R" %in% missing_optional) {
    notes <- c(notes, paste0(
      "missing: ", file.path("src", "rzig", "tools", "fetch_zig.R"),
      " (used only to download Zig during installation); run update_rzig(path)"
    ))
  }
  if ("tools/imports.R" %in% missing_optional) {
    notes <- c(notes, paste0(
      "missing: ", file.path("src", "rzig", "tools", "imports.R"),
      " (used only for Config/rzig/imports); run update_rzig(path)"
    ))
  }
  if (length(missing_framework) || length(missing_templates)) {
    problems <- c(problems, paste0(
      "missing: ",
      paste(file.path("src", "rzig", c(missing_framework, missing_templates)), collapse = ", "),
      "; run update_rzig(path)"
    ))
  }
  if (length(outdated)) {
    problems <- c(problems, sprintf(
      "%d framework file%s differ%s from rzig %s (%s); run update_rzig(path), which keeps src/rzig/src and customized build files",
      length(outdated), if (length(outdated) == 1L) "" else "s",
      if (length(outdated) == 1L) "s" else "",
      as.character(utils::packageVersion("rzig")),
      paste(utils::head(outdated, 3L), collapse = ", ")
    ))
  }
  if (!is.null(package)) {
    customized <- character()
    for (pair in .rzig_template_pairs(package)) {
      target <- file.path(path, pair$file)
      if (file.exists(target) && !.rzig_same_text(target, pair$template, pair$package)) {
        customized <- c(customized, pair$file)
      }
    }
    present_templates <- setdiff(zig_templates, c(missing_templates, authored))
    for (file in present_templates) {
      if (!.rzig_same_text(file.path(path, "src", "rzig", file), file.path(assets, file))) {
        customized <- c(customized, file.path("src", "rzig", file))
      }
    }
    if (length(customized)) {
      notes <- c(notes, paste0(
        "differs from the rzig template: ", paste(customized, collapse = ", ")
      ))
    }
  }
  absent <- .rzig_c_library_files_missing(path)
  if (length(absent)) {
    problems <- c(problems, paste0(
      "src/rzig/c_libraries.zon names files that do not exist: ",
      paste(file.path("src", "rzig", absent), collapse = ", ")
    ))
  }
  foreign <- .rzig_foreign_sources(path)
  if (.rzig_is_mixed(path)) {
    makevars_in <- .rzig_read_text(file.path(path, "src", "Makevars.in")) %||% ""
    if (!grepl("@RZIG_OBJECTS@", makevars_in, fixed = TRUE)) {
      problems <- c(problems, paste0(
        "Config/rzig/mixed is set, but src/Makevars.in has no @RZIG_OBJECTS@, so only src/entry.c ",
        "is compiled; update_rzig(path) installs the current templates"
      ))
    }
    if (length(foreign)) {
      notes <- c(notes, paste0(
        "compiled by R's compilers (Config/rzig/mixed): ", paste(file.path("src", foreign), collapse = ", ")
      ))
    }
    if (!length(.rzig_register_callers(path))) {
      problems <- c(problems, paste0(
        "Config/rzig/mixed leaves R_init_", .rzig_c_identifier(package), "() to the package, but no C or ",
        "C++ source of src/ calls rzig_register(); see ?use_rzig_mixed"
      ))
    }
  } else if (length(foreign)) {
    problems <- c(problems, paste0(
      "not compiled by the rzig build: ", paste(file.path("src", foreign), collapse = ", "),
      "; the generated Makevars build the Zig sources and src/entry.c only; ",
      "use_rzig_mixed(path) builds them with R's compilers"
    ))
  }
  makevars <- .rzig_foreign_makevars(path)
  if (length(makevars)) {
    problems <- c(problems, paste0(
      paste(makevars, collapse = " and "), " written by hand: configure overwrites ",
      "it and cleanup removes it; move its settings into the .in templates"
    ))
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
  if (is.null(fields) || !nzchar(.rzig_field(fields, "Package") %||% "")) {
    return(.rzig_check_result("DESCRIPTION has no Package field"))
  }
  problems <- character()
  version <- .rzig_field(fields, "Version") %||% ""
  if (is.na(package_version(version, strict = FALSE))) {
    problems <- c(problems, sprintf("Version \"%s\" is not a valid package version", version))
  }
  wanted <- c("Title", "Description", "License")
  missing <- wanted[!wanted %in% names(fields)]
  if (!any(c("Authors@R", "Maintainer") %in% names(fields))) missing <- c(missing, "Authors@R")
  notes <- if (length(missing)) {
    paste("R CMD check also requires", paste(missing, collapse = ", "))
  } else character()
  if (!grepl("zig", .rzig_field(fields, "SystemRequirements") %||% "", ignore.case = TRUE)) {
    notes <- c(notes, sprintf(
      "SystemRequirements does not name Zig; state the supported series, for example \"Zig %s\"",
      .rzig_zig_series_label()
    ))
  }
  lines <- strsplit(.rzig_normalize_newlines(.rzig_read_text(file)), "\n", fixed = TRUE)[[1L]]
  listed <- .rzig_description_field(lines, .rzig_extra_sources_field)$entries
  if (!all(.rzig_extra_sources %in% listed)) {
    notes <- c(notes, paste0(
      .rzig_extra_sources_field, " does not list the Zig sources, so devtools::load_all() ",
      "misses changes to them; use_rzig() adds ", paste(.rzig_extra_sources, collapse = ", ")
    ))
  }
  problems <- c(problems, .rzig_check_imports(path))
  if (isTRUE(tolower(trimws(.rzig_field(fields, "Config/rzig/download-zig") %||% "")) %in% c("true", "yes"))) {
    notes <- c(notes, paste0(
      "Config/rzig/download-zig: configure downloads a verified Zig when it finds none; ",
      "CRAN does not allow that without its consent, so a package for CRAN leaves the field out"
    ))
  }
  sources <- list.files(file.path(path, "src", "rzig", "src"), pattern = "\\.zig$", recursive = TRUE, full.names = TRUE)
  uses_lapack <- any(vapply(sources, function(source) {
    grepl("rzig\\.(Blas|Lapack)\\.", .rzig_read_text(source) %||% "")
  }, logical(1L)))
  if (uses_lapack && !.rzig_links_lapack(path)) {
    notes <- c(notes, paste0(
      "the Zig code calls rzig.Blas or rzig.Lapack, but DESCRIPTION does not ask to link them; ",
      "run use_rzig_lapack(path)"
    ))
  }
  .rzig_check_result(problems, notes)
}

`%||%` <- function(x, y) if (is.null(x) || (length(x) == 1L && is.na(x))) y else x

# A DESCRIPTION field from read.dcf(), or NA when the field is absent.
.rzig_field <- function(fields, name) {
  if (name %in% names(fields)) unname(fields[[name]]) else NA_character_
}

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

# The paths that src/rzig/c_libraries.zon names (string literals ending in a C
# source or header suffix, or under `.include`) and that do not exist. The
# file is ZON; this reads its string literals outside comments.
.rzig_c_library_files_missing <- function(path) {
  file <- file.path(path, "src", "rzig", "c_libraries.zon")
  text <- .rzig_read_text(file)
  if (is.null(text)) return(character())
  lines <- strsplit(.rzig_normalize_newlines(text), "\n", fixed = TRUE)[[1L]]
  lines <- sub("//.*$", "", lines)
  literals <- unlist(regmatches(lines, gregexpr("\"[^\"]*\"", lines)), use.names = FALSE)
  literals <- substring(literals, 2L, nchar(literals) - 1L)
  include <- unlist(regmatches(lines, gregexpr("\\.include[[:space:]]*=[[:space:]]*\\.\\{[^}]*\\}", lines)), use.names = FALSE)
  directories <- unlist(regmatches(include, gregexpr("\"[^\"]*\"", include)), use.names = FALSE)
  directories <- substring(directories, 2L, nchar(directories) - 1L)
  files <- literals[grepl("\\.(c|h|cc|cpp|cxx|hpp|S|s)$", literals)]
  candidates <- unique(c(files, directories))
  candidates[!file.exists(file.path(path, "src", "rzig", candidates))]
}
