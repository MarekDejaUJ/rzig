#' Link the LAPACK and BLAS libraries of R
#'
#' Adds `Config/rzig/lapack: true` to `DESCRIPTION`. The generated
#' `configure` then links `$(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)`, the libraries
#' that `rzig.Blas` and `rzig.Lapack` call, in the order *Writing R
#' Extensions* asks for. `$(FLIBS)` is the Fortran runtime of R: on macOS,
#' installing such a package from source needs the gfortran that CRAN's R
#' builds use (<https://mac.r-project.org/tools/>), on Windows it comes with
#' Rtools.
#'
#' @param path Path to a package previously initialized with [use_rzig()].
#'
#' @return The path of `DESCRIPTION`, invisibly.
#' @examples
#' package_path <- tempfile("rzig-lapack-", tmpdir = tempdir())
#' dir.create(package_path)
#' writeLines(c("Package: examplepkg", "Version: 0.0.1"),
#'   file.path(package_path, "DESCRIPTION"))
#' use_rzig(package_path)
#' use_rzig_lapack(package_path)
#' read.dcf(file.path(package_path, "DESCRIPTION"), fields = "Config/rzig/lapack")
#' unlink(package_path, recursive = TRUE)
#' @export
use_rzig_lapack <- function(path) {
  info <- .rzig_package_info(path)
  file <- file.path(info$path, "DESCRIPTION")
  lines <- strsplit(.rzig_normalize_newlines(.rzig_read_text(file)), "\n", fixed = TRUE)[[1L]]
  field <- .rzig_description_field(lines, .rzig_lapack_field)
  line <- paste0(.rzig_lapack_field, ": true")
  if (is.na(field$start)) {
    lines <- c(lines, line)
  } else {
    lines <- c(lines[seq_len(field$start - 1L)], line, lines[seq.int(field$end + 1L, length.out = length(lines) - field$end)])
  }
  .rzig_write_text(paste0(paste(lines, collapse = "\n"), "\n"), file)
  makevars <- .rzig_read_text(file.path(info$path, "src", "Makevars.in")) %||% ""
  if (!grepl("@RZIG_LAPACK_LIBS@", makevars, fixed = TRUE)) {
    warning("src/Makevars.in has no @RZIG_LAPACK_LIBS@; update_rzig(path) installs the Makevars templates ",
      "that link the libraries", call. = FALSE)
  }
  message("Package ", info$package, " links the LAPACK and BLAS of R")
  invisible(file)
}

.rzig_lapack_field <- "Config/rzig/lapack"

# Whether DESCRIPTION asks configure to link LAPACK and BLAS.
.rzig_links_lapack <- function(path) {
  fields <- tryCatch(read.dcf(file.path(path, "DESCRIPTION"))[1L, ], error = function(error) NULL)
  value <- if (is.null(fields)) NA_character_ else .rzig_field(fields, .rzig_lapack_field)
  isTRUE(tolower(trimws(value)) %in% c("true", "yes"))
}
