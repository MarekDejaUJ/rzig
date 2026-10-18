# The case-study package of the article on rzig (probabilities of causation
# by an exact linear program), shipped in inst/examples/poclp, assembled as
# the replication script of the article assembles it.

assemble_poclp <- function(root) {
  source <- system.file("examples", "poclp", package = "rzig")
  path <- file.path(root, "poclp")
  dir.create(path)
  file.copy(file.path(source, "DESCRIPTION"), path)
  suppressMessages(use_rzig(path))
  file.copy(list.files(file.path(source, "src", "rzig", "src"), full.names = TRUE),
    file.path(path, "src", "rzig", "src"), overwrite = TRUE)
  file.copy(file.path(source, "R", "methods.R"), file.path(path, "R"))
  namespace <- readLines(file.path(path, "NAMESPACE"))
  writeLines(c("S3method(print, poc_bounds)", "", namespace), file.path(path, "NAMESPACE"))
  suppressMessages(document(path))
  path
}

test_that("the case-study package scans and passes the checks", {
  root <- local_tempdir()
  path <- assemble_poclp(root)
  exports <- scan_exports(path)
  expect_identical(vapply(exports, function(item) item$name, character(1L)), c("lp_solve", "poc_bounds", "poc_grid"))
  status <- rzig_status(path)
  expect_true(all(status$ok[status$step %in% c("DESCRIPTION", "Scaffold", "Zig source", "Exports", "Bindings")]))
})

test_that("the bounds of the case study contain the true probabilities", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  root <- local_tempdir()
  path <- assemble_poclp(root)
  lib <- file.path(root, "lib")
  dir.create(lib)
  built <- suppressWarnings(build_zig(path, lib = lib))
  expect_true(built$ok, info = paste(built$log, collapse = "\n"))
  output <- run_r(paste(
    sprintf(".libPaths(c(%s, .libPaths()))", deparse(lib)),
    "library(poclp)",
    "q <- rbind(0.5 * c(0.5, 0.2, 0.2, 0.1), 0.5 * c(0.3, 0.4, 0.1, 0.2))",
    "observed <- rbind(c(sum(q[1, 1:2]), sum(q[1, 3:4])), c(sum(q[2, c(1, 3)]), sum(q[2, c(2, 4)])))",
    "experimental <- rbind(c(sum(q[, 1:2]), sum(q[, 3:4])), c(sum(q[, c(1, 3)]), sum(q[, c(2, 4)])))",
    "truth <- c(sum(q[, 2]), q[2, 2] / observed[2, 2], q[1, 2] / observed[1, 1])",
    "b <- matrix(unclass(poc_bounds(observed, experimental, x = 2, y = 2, x_prime = 1, y_prime = 1)), ncol = 2, byrow = TRUE)",
    "cat('contains', all(b[, 1] <= truth + 1e-9 & truth <= b[, 2] + 1e-9), '\\n')",
    sep = "\n"
  ))
  expect_match(output, "contains TRUE", fixed = TRUE)
})
