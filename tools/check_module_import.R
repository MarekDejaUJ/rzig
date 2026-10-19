# CRAN-style check of a package that imports a Zig module of another package
# (CI job client-check): a providing package with inst/zig/kernels/root.zig
# is installed, and a second package that imports the module through
# Config/rzig/imports and LinkingTo must pass R CMD check --as-cran without
# NOTE, WARNING or ERROR.
#
# Usage: Rscript tools/check_module_import.R
# Needs rzig installed and a supported Zig compiler (ZIG or PATH).

stopifnot(requireNamespace("rzig", quietly = TRUE))

# system2(env = ) puts the variables on the command line, and R on Windows
# ignores NAME=value arguments before CMD; the variables are therefore set in
# this process for the duration of the call, as build_zig() does.
with_environment <- function(environment, code) {
  names <- sub("=.*$", "", environment)
  values <- substring(environment, nchar(names) + 2L)
  old <- Sys.getenv(names, unset = NA, names = TRUE)
  do.call(Sys.setenv, as.list(stats::setNames(values, names)))
  on.exit({
    unset <- is.na(old)
    if (any(unset)) Sys.unsetenv(names[unset])
    if (any(!unset)) do.call(Sys.setenv, as.list(old[!unset]))
  }, add = TRUE)
  force(code)
}
compiler <- rzig::find_zig()
work <- tempfile("rzig-module-check-")
dir.create(work)
lib <- file.path(work, "lib")
dir.create(lib)
fields <- function(title) list(
  Title = title,
  Description = paste(
    "Shares 'Zig' code between packages through a module that",
    "'rzig' compiles into the importing package; used in checks."
  ),
  "Authors@R" = 'person("A", "Author", email = "a@example.org", role = c("aut", "cre"))'
)
module_header <- c(
  "const rzig = @import(\"rzig\");",
  "const kernels = @import(\"kernels\");",
  "",
  "pub const panic = rzig.Panic;",
  "",
  "comptime {",
  "    rzig.registerModule(@This());",
  "}",
  ""
)

provider <- file.path(work, "kernelpkg")
rzig::create_rzig_package(provider, fields = fields("Provides a 'Zig' Module"), tests = FALSE)
rzig::use_rzig_module(provider, "kernels")
writeLines(c(module_header,
  "/// The sum of the values.",
  "/// @param x A numeric vector.",
  "/// @return A number.",
  "/// @examples",
  "/// kernel_sum(c(1, 2, 3))",
  "/// @export",
  "pub fn kernel_sum(x: []const f64) f64 {",
  "    return kernels.sum(x);",
  "}"
), file.path(provider, "src", "rzig", "src", "main.zig"))
rzig::document(provider)
installed <- rzig::build_zig(provider, lib = lib)
print(installed)
stopifnot(installed$ok)

consumer <- file.path(work, "userpkg")
rzig::create_rzig_package(consumer, fields = fields("Uses a 'Zig' Module of Another Package"))
rzig::use_rzig_import(consumer, "kernelpkg", "kernels")
writeLines(c(module_header,
  "/// Twice the sum of the values, by the module of kernelpkg.",
  "/// @param x A numeric vector.",
  "/// @return A number.",
  "/// @examples",
  "/// user_total(c(1, 2, 3))",
  "/// @export",
  "pub fn user_total(x: []const f64) f64 {",
  "    return 2 * kernels.sum(x);",
  "}"
), file.path(consumer, "src", "rzig", "src", "main.zig"))
unlink(list.files(file.path(consumer, "tests", "testthat"), pattern = "^test-", full.names = TRUE))
writeLines(c(
  "test_that(\"the imported module computes the total\", {",
  "  expect_identical(user_total(c(1, 2, 3)), 12)",
  "})"
), file.path(consumer, "tests", "testthat", "test-total.R"))
rzig::document(consumer)
old_paths <- .libPaths()
.libPaths(c(lib, old_paths))
status <- rzig::rzig_status(consumer)
print(status)
stopifnot(all(status$ok))

old <- setwd(work)
on.exit(setwd(old), add = TRUE)
r <- file.path(R.home("bin"), "R")
# The compiler flags of a developer's ~/.R/Makevars are not CRAN's.
build <- with_environment(
  c(paste0("R_LIBS=", paste(c(lib, old_paths), collapse = .Platform$path.sep)), "R_MAKEVARS_USER=/dev/null"),
  system2(r, c("CMD", "build", "userpkg"), stdout = TRUE, stderr = TRUE))
cat(build, sep = "\n")
stopifnot(is.null(attr(build, "status")))
tarball <- list.files(work, pattern = "^userpkg_.*\\.tar\\.gz$")
check_tmp <- file.path(work, "check-tmp")
dir.create(check_tmp)
environment <- c(
  paste0("ZIG=", compiler$path),
  paste0("TMPDIR=", check_tmp),
  paste0("R_LIBS=", paste(c(lib, old_paths), collapse = .Platform$path.sep)),
  "R_MAKEVARS_USER=/dev/null",
  "_R_CHECK_CRAN_INCOMING_=false",
  "_R_CHECK_CRAN_INCOMING_REMOTE_=false",
  "_R_CHECK_LIMIT_CORES_=TRUE",
  "_R_CHECK_INSTALL_TIMING_CPU_TO_ELAPSED_THRESHOLD_=2.5",
  "_R_CHECK_THINGS_IN_TEMP_DIR_=true",
  "_R_CHECK_FORCE_SUGGESTS_=false",
  "_R_CHECK_FUTURE_FILE_TIMESTAMPS_=false",
  "_R_CHECK_RD_VALIDATE_RD2HTML_=false"
)
check <- with_environment(environment, system2(r,
  c("CMD", "check", "--as-cran", "--no-manual", tarball), stdout = TRUE, stderr = TRUE))
log <- readLines(file.path(work, "userpkg.Rcheck", "00check.log"))
cat(log, sep = "\n")
flagged <- grep("\\.\\.\\. (NOTE|WARNING|ERROR)", log, value = TRUE)
status_line <- grep("^Status:", log, value = TRUE)
if (length(flagged) || !identical(status_line, "Status: OK")) {
  stop("the importing package did not pass R CMD check cleanly: ",
    paste(c(flagged, status_line), collapse = "; "), call. = FALSE)
}
cat("package importing a Zig module of another package: R CMD check --as-cran Status OK\n")
