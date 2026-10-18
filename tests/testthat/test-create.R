test_that("create_rzig_package creates a documented package with tests", {
  root <- local_tempdir()
  path <- file.path(root, "zigstats")
  created <- suppressMessages(create_rzig_package(path, fields = list(Title = "Rank Statistics in 'Zig'")))
  expect_identical(created, normalizePath(path))
  description <- read.dcf(file.path(path, "DESCRIPTION"))[1L, ]
  expect_identical(unname(description[["Package"]]), "zigstats")
  expect_identical(unname(description[["Title"]]), "Rank Statistics in 'Zig'")
  expect_identical(unname(description[["License"]]), "GPL-3")
  expect_match(description[["SystemRequirements"]], "Zig 0.16.x or 0.17.x", fixed = TRUE)
  expect_match(description[["Suggests"]], "testthat", fixed = TRUE)
  expect_true(all(file.exists(file.path(path, c(
    "NAMESPACE", "R/rzig-wrappers.R", "man/hello_zig.Rd", "src/rzig/src/main.zig",
    "tests/testthat.R", "tests/testthat/test-hello-zig.R"
  )))))
  expect_false(file.exists(file.path(path, ".github")))
  status <- rzig_status(path)
  expect_true(all(status$ok))
  expect_error(create_rzig_package(path), "exists and is not empty")
})

test_that("create_rzig_package validates its arguments", {
  root <- local_tempdir()
  expect_error(create_rzig_package(file.path(root, "1pkg")), "not a valid package name")
  expect_error(create_rzig_package(file.path(root, "my_pkg")), "not a valid package name")
  expect_error(create_rzig_package(file.path(root, "okpkg"), fields = list("x")), "named list")
  expect_error(create_rzig_package(file.path(root, "okpkg"), tests = NA), "TRUE or FALSE")
  path <- file.path(root, "cipkg")
  suppressMessages(create_rzig_package(path, tests = FALSE, ci = TRUE))
  expect_true(file.exists(file.path(path, ".github", "workflows", "rzig-check.yaml")))
  expect_false(dir.exists(file.path(path, "tests")))
  expect_false("Suggests" %in% colnames(read.dcf(file.path(path, "DESCRIPTION"))))
})

test_that("a created package builds and passes its own tests", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  root <- local_tempdir()
  path <- file.path(root, "zigcreated")
  suppressMessages(create_rzig_package(path))
  lib <- file.path(root, "lib")
  dir.create(lib)
  result <- suppressWarnings(build_zig(path, lib = lib))
  expect_true(result$ok)
  output <- run_r(sprintf(paste0(
    ".libPaths(c(%s, .libPaths())); library(testthat); ",
    "r <- as.data.frame(test_dir(%s, package = 'zigcreated', load_package = 'installed', reporter = 'silent')); ",
    "cat('FAILED', sum(r$failed) + sum(r$error), 'PASSED', sum(r$passed), '\\n')"
  ), deparse(lib), deparse(file.path(path, "tests", "testthat"))))
  expect_true(any(grepl("FAILED 0 PASSED 1", output, fixed = TRUE)))
})
