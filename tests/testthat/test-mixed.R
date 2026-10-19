legacy_c <- c(
  "#include <Rinternals.h>",
  "",
  "SEXP legacy_add(SEXP a, SEXP b) {",
  "    return Rf_ScalarReal(Rf_asReal(a) + Rf_asReal(b));",
  "}",
  "",
  "void legacy_scale(double *x, int *n, double *factor) {",
  "    for (int i = 0; i < *n; i++) x[i] *= *factor;",
  "}"
)

legacy_cpp <- c(
  "#include <vector>",
  "#include <numeric>",
  "#include <Rinternals.h>",
  "",
  "extern \"C\" SEXP legacy_sum(SEXP x) {",
  "    std::vector<double> values(REAL(x), REAL(x) + XLENGTH(x));",
  "    return Rf_ScalarReal(std::accumulate(values.begin(), values.end(), 0.0));",
  "}"
)

init_c <- function(package) c(
  "#include <Rinternals.h>",
  "#include <R_ext/Rdynload.h>",
  "",
  "SEXP legacy_add(SEXP a, SEXP b);",
  "SEXP legacy_sum(SEXP x);",
  "void legacy_scale(double *x, int *n, double *factor);",
  "void rzig_register(DllInfo *dll, const R_CMethodDef *c_methods,",
  "                   const R_CallMethodDef *call_methods,",
  "                   const R_FortranMethodDef *fortran_methods,",
  "                   const R_ExternalMethodDef *external_methods);",
  "",
  "static const R_CMethodDef c_methods[] = {",
  "    {\"legacy_scale\", (DL_FUNC) &legacy_scale, 3, NULL},",
  "    {NULL, NULL, 0, NULL}",
  "};",
  "",
  "static const R_CallMethodDef call_methods[] = {",
  "    {\"legacy_add\", (DL_FUNC) &legacy_add, 2},",
  "    {\"legacy_sum\", (DL_FUNC) &legacy_sum, 1},",
  "    {NULL, NULL, 0}",
  "};",
  "",
  sprintf("void R_init_%s(DllInfo *dll) {", package),
  "    rzig_register(dll, c_methods, call_methods, NULL, NULL);",
  "}"
)

test_that("C sources stop use_rzig() unless the package is mixed", {
  path <- local_package("mixedguard")
  dir.create(file.path(path, "src"))
  writeLines(legacy_c, file.path(path, "src", "legacy.c"))
  expect_error(use_rzig(path), "use_rzig(path, mixed = TRUE)", fixed = TRUE)
  expect_error(use_rzig(path, mixed = NA), "`mixed` must be TRUE or FALSE")
  suppressMessages(use_rzig(path, mixed = TRUE))
  expect_true(rzig:::.rzig_is_mixed(path))
  scaffold <- rzig:::.rzig_check_scaffold(path, "mixedguard")
  expect_true(any(grepl("calls rzig_register()", scaffold$problems, fixed = TRUE)))
  expect_true(any(grepl("compiled by R's compilers (Config/rzig/mixed): src/legacy.c", scaffold$notes, fixed = TRUE)))
  writeLines(init_c("mixedguard"), file.path(path, "src", "init.c"))
  expect_length(rzig:::.rzig_check_scaffold(path, "mixedguard")$problems, 0L)
  expect_match(paste(readLines(file.path(path, "src", "entry.c")), collapse = "\n"), "#ifndef RZIG_MIXED", fixed = TRUE)
})

test_that("use_rzig_mixed() sets one field and warns about old templates", {
  path <- local_package("mixedfield")
  suppressMessages(use_rzig(path))
  expect_false(rzig:::.rzig_is_mixed(path))
  expect_message(use_rzig_mixed(path), "builds its C, C++ and Fortran sources", fixed = TRUE)
  suppressMessages(use_rzig_mixed(path))
  expect_identical(sum(grepl("^Config/rzig/mixed:", readLines(file.path(path, "DESCRIPTION")))), 1L)
  makevars <- file.path(path, "src", "Makevars.in")
  writeLines(sub("@RZIG_OBJECTS@", "OBJECTS = entry.o", readLines(makevars), fixed = TRUE), makevars)
  expect_warning(suppressMessages(use_rzig_mixed(path)), "@RZIG_OBJECTS@")
  expect_true(any(grepl("@RZIG_OBJECTS@", rzig:::.rzig_check_scaffold(path, "mixedfield")$problems, fixed = TRUE)))
})

test_that("a mixed package calls its C, C++ and Zig routines", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  root <- local_tempdir()
  path <- file.path(root, "mixedpkg")
  suppressMessages(create_rzig_package(path, tests = FALSE))
  writeLines(legacy_c, file.path(path, "src", "legacy.c"))
  writeLines(legacy_cpp, file.path(path, "src", "legacy_sum.cpp"))
  writeLines(init_c("mixedpkg"), file.path(path, "src", "init.c"))
  writeLines(c(
    "legacy_add <- function(a, b) .Call(c_legacy_add, a, b)",
    "legacy_sum <- function(x) .Call(c_legacy_sum, as.numeric(x))",
    "legacy_scale <- function(x, factor) .C(c_legacy_scale, as.numeric(x), length(x), as.numeric(factor))[[1L]]"
  ), file.path(path, "R", "legacy.R"))
  cat("useDynLib(mixedpkg, .registration = TRUE, .fixes = \"c_\")",
    "export(legacy_add, legacy_sum, legacy_scale)", sep = "\n",
    file = file.path(path, "NAMESPACE"), append = TRUE)
  suppressMessages(use_rzig_mixed(path))
  suppressMessages(document(path))
  lib <- file.path(root, "lib")
  dir.create(lib)
  result <- suppressWarnings(build_zig(path, lib = lib))
  expect_true(result$ok, info = paste(result$log, collapse = "\n"))
  output <- run_r(paste(
    sprintf(".libPaths(c(%s, .libPaths()))", deparse(lib)),
    "library(mixedpkg)",
    "cat('zig', hello_zig('R'), '\\n')",
    "cat('add', legacy_add(2, 3), '\\n')",
    "cat('sum', legacy_sum(1:4), '\\n')",
    "cat('scale', legacy_scale(c(1, 2), 3), '\\n')",
    "cat('string', .Call('legacy_add', 1, 1, PACKAGE = 'mixedpkg'), '\\n')",
    sep = "\n"
  ))
  expect_identical(attr(output, "status"), NULL, info = output)
  expect_match(output, "zig .+", info = output)
  expect_match(output, "add 5", fixed = TRUE)
  expect_match(output, "sum 10", fixed = TRUE)
  expect_match(output, "scale 3 6", fixed = TRUE)
  expect_match(output, "string 2", fixed = TRUE)
})
