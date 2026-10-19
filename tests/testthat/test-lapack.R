# Whether the Fortran runtime that $(FLIBS) names can be linked here.
flibs_available <- function() {
  flags <- suppressWarnings(system2(file.path(R.home("bin"), "R"), c("CMD", "config", "FLIBS"), stdout = TRUE))
  directories <- sub("^-L", "", grep("^-L", strsplit(paste(flags, collapse = " "), "[[:space:]]+")[[1L]], value = TRUE))
  length(directories) == 0L || all(dir.exists(directories))
}

test_that("use_rzig_lapack asks configure to link LAPACK and BLAS", {
  path <- local_package("lapackfield")
  suppressMessages(use_rzig(path))
  expect_false(rzig:::.rzig_links_lapack(path))
  suppressMessages(use_rzig_lapack(path))
  expect_true(rzig:::.rzig_links_lapack(path))
  suppressMessages(use_rzig_lapack(path))
  expect_identical(sum(grepl("^Config/rzig/lapack:", readLines(file.path(path, "DESCRIPTION")))), 1L)
  file.copy(fixture_path("lapack.zig"), file.path(path, "src", "rzig", "src", "main.zig"), overwrite = TRUE)
  expect_false(any(grepl("use_rzig_lapack", rzig:::.rzig_check_description(path)$notes)))
  writeLines(setdiff(readLines(file.path(path, "DESCRIPTION")), "Config/rzig/lapack: true"), file.path(path, "DESCRIPTION"))
  expect_true(any(grepl("use_rzig_lapack", rzig:::.rzig_check_description(path)$notes)))
})

test_that("BLAS and LAPACK routines agree with R's linear algebra", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  skip_if_not(flibs_available(), "the Fortran runtime of R is not installed")
  root <- local_tempdir()
  path <- file.path(root, "lapackpkg")
  suppressMessages(create_rzig_package(path, tests = FALSE))
  suppressMessages(use_rzig_lapack(path))
  file.copy(fixture_path("lapack.zig"), file.path(path, "src", "rzig", "src", "main.zig"), overwrite = TRUE)
  suppressMessages(document(path))
  lib <- file.path(root, "lib")
  dir.create(lib)
  result <- suppressWarnings(build_zig(path, lib = lib))
  expect_true(result$ok, info = paste(result$log, collapse = "\n"))
  script <- file.path(root, "compare.R")
  writeLines(c(
    sprintf(".libPaths(c(%s, .libPaths()))", deparse(lib)),
    "library(lapackpkg)",
    "set.seed(1)",
    "a <- matrix(rnorm(12), 4)",
    "b <- matrix(rnorm(9), 3)",
    "s <- crossprod(matrix(rnorm(16), 4)) + diag(4)",
    "y <- rnorm(4)",
    "near <- function(x, y) isTRUE(all.equal(x, y, tolerance = 1e-10, check.attributes = FALSE))",
    "r <- chol(s)",
    "checks <- c(",
    "  gemm = near(la_gemm(a, b, FALSE), a %*% b),",
    "  gemm_t = near(la_gemm(a, a, TRUE), crossprod(a)),",
    "  gemv = near(la_gemv(a, b[, 1]), drop(a %*% b[, 1])),",
    "  syrk = near(la_crossprod(a), crossprod(a)),",
    "  trsm = near(la_backsolve(r, diag(4)), backsolve(r, diag(4))),",
    "  potrf = near(la_chol(s), r),",
    "  potrs = near(drop(la_chol_solve(s, cbind(y))), solve(s, y)),",
    "  gesv = near(la_solve(s, cbind(y, 2 * y)), solve(s, cbind(y, 2 * y))),",
    "  geqrf = near(abs(la_qr_r(a)), abs(qr.R(qr(a)))),",
    "  ormqr = near(abs(la_qr_q1(a)), abs(qr.Q(qr(a))[, 1])),",
    "  gels = near(la_lstsq(a, y), qr.solve(a, y)),",
    "  syevr = near(rev(la_eigen(s)), eigen(s, symmetric = TRUE)$values),",
    "  gesdd = near(la_svd(a), svd(a)$d)",
    ")",
    "cat(paste(names(checks), checks), sep = '\\n')",
    "cat(tryCatch(la_chol(matrix(c(1, 2, 2, 1), 2)), error = conditionMessage), '\\n')",
    "cat(tryCatch(la_solve(matrix(0, 2, 2), diag(2)), error = conditionMessage), '\\n')",
    "cat(tryCatch(la_gemm(a, a, FALSE), error = conditionMessage), '\\n')"
  ), script)
  output <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", shQuote(script)),
    stdout = TRUE, stderr = TRUE))
  for (name in c("gemm", "gemm_t", "gemv", "syrk", "trsm", "potrf", "potrs", "gesv", "geqrf", "ormqr", "gels",
                 "syevr", "gesdd")) {
    expect_true(paste(name, "TRUE") %in% output, info = paste(output, collapse = "\n"))
  }
  expect_true(any(grepl("not positive definite (leading minor 2)", output, fixed = TRUE)))
  expect_true(any(grepl("exactly singular", output, fixed = TRUE)))
  expect_true(any(grepl("inner dimensions differ", output, fixed = TRUE)))
})
