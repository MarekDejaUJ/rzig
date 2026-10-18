#' Build C, C++ and Fortran sources next to the Zig code
#'
#' Adds `Config/rzig/mixed: true` to `DESCRIPTION`. The generated `configure`
#' then leaves `OBJECTS` unset, so that R compiles every C, C++ and Fortran
#' source file of `src/` with its own compilers and links them with the Zig
#' library, and `src/entry.c` leaves `R_init_<pkg>` to the package. The
#' package's `R_init_<pkg>` registers its own routines with
#' `rzig_register()`, which adds the Zig routines to the `.Call` routines:
#'
#' ```c
#' #include <R_ext/Rdynload.h>
#'
#' void rzig_register(DllInfo *dll, const R_CMethodDef *c_methods,
#'                    const R_CallMethodDef *call_methods,
#'                    const R_FortranMethodDef *fortran_methods,
#'                    const R_ExternalMethodDef *external_methods);
#'
#' static const R_CallMethodDef call_methods[] = {
#'     {"legacy_add", (DL_FUNC) &legacy_add, 2},
#'     {NULL, NULL, 0}
#' };
#'
#' void R_init_mypkg(DllInfo *dll) {
#'     rzig_register(dll, NULL, call_methods, NULL, NULL);
#' }
#' ```
#'
#' Dynamic symbol lookup stays disabled; the R code may name the routines by
#' symbol or by string. A C routine with the name of a Zig export is not
#' registered (a message says so when the package loads). [use_rzig()] with
#' `mixed = TRUE` calls this function before it scaffolds the package.
#'
#' @param path Path to the package root.
#'
#' @return The path of `DESCRIPTION`, invisibly.
#' @examples
#' package_path <- tempfile("rzig-mixed-", tmpdir = tempdir())
#' dir.create(package_path)
#' writeLines(c("Package: examplepkg", "Version: 0.0.1"),
#'   file.path(package_path, "DESCRIPTION"))
#' use_rzig_mixed(package_path)
#' read.dcf(file.path(package_path, "DESCRIPTION"), fields = "Config/rzig/mixed")
#' unlink(package_path, recursive = TRUE)
#' @export
use_rzig_mixed <- function(path) {
  info <- .rzig_package_info(path)
  file <- .rzig_set_config_true(info$path, .rzig_mixed_field)
  makevars <- .rzig_read_text(file.path(info$path, "src", "Makevars.in"))
  if (!is.null(makevars) && !grepl("@RZIG_OBJECTS@", makevars, fixed = TRUE)) {
    warning("src/Makevars.in has no @RZIG_OBJECTS@; update_rzig(path) installs the Makevars templates ",
      "that compile the other sources", call. = FALSE)
  }
  message("Package ", info$package, " builds its C, C++ and Fortran sources next to the Zig code")
  invisible(file)
}

.rzig_mixed_field <- "Config/rzig/mixed"

# Whether DESCRIPTION asks configure to compile the other sources of src/.
.rzig_is_mixed <- function(path) {
  fields <- tryCatch(read.dcf(file.path(path, "DESCRIPTION"))[1L, ], error = function(error) NULL)
  value <- if (is.null(fields)) NA_character_ else .rzig_field(fields, .rzig_mixed_field)
  isTRUE(tolower(trimws(value)) %in% c("true", "yes"))
}

# Set a Config/rzig/ field of DESCRIPTION to true, keeping every other line.
.rzig_set_config_true <- function(path, field_name) {
  file <- file.path(path, "DESCRIPTION")
  lines <- strsplit(.rzig_normalize_newlines(.rzig_read_text(file)), "\n", fixed = TRUE)[[1L]]
  field <- .rzig_description_field(lines, field_name)
  line <- paste0(field_name, ": true")
  if (is.na(field$start)) {
    lines <- c(lines, line)
  } else {
    lines <- c(lines[seq_len(field$start - 1L)], line, lines[seq.int(field$end + 1L, length.out = length(lines) - field$end)])
  }
  .rzig_write_text(paste0(paste(lines, collapse = "\n"), "\n"), file)
  file
}

# The C and C++ sources of a mixed package that call rzig_register().
.rzig_register_callers <- function(path) {
  sources <- list.files(file.path(path, "src"), pattern = "\\.(c|cc|cpp|cxx|C)$", full.names = TRUE)
  sources <- sources[basename(sources) != "entry.c"]
  calls <- vapply(sources, function(source) {
    grepl("rzig_register[[:space:]]*\\(", .rzig_read_text(source) %||% "")
  }, logical(1L))
  basename(sources[calls])
}
