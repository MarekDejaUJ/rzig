test_that("pure Zig work can run in parallel without exposing R", {
  values <- as.numeric(seq_len(10000L))
  expect_identical(parallel_square(values), values * values)
  expect_identical(parallel_square(numeric()), numeric())
})

test_that("the number of worker threads follows the environment limits", {
  names <- c("RZIG_NUM_THREADS", "OMP_THREAD_LIMIT", "_R_CHECK_LIMIT_CORES_")
  old <- Sys.getenv(names, unset = NA)
  on.exit(for (name in names) {
    if (is.na(old[[name]])) Sys.unsetenv(name) else do.call(Sys.setenv, as.list(old[name]))
  }, add = TRUE)
  Sys.unsetenv(names)
  cores <- min(parallel_thread_count(1000L), 32L)
  expect_gte(cores, 1L)
  expect_identical(parallel_thread_count(1L), 1L)
  Sys.setenv(RZIG_NUM_THREADS = "1")
  expect_identical(parallel_thread_count(1000L), 1L)
  Sys.setenv(RZIG_NUM_THREADS = "two")
  expect_error(parallel_thread_count(1000L), "RZIG_NUM_THREADS must be a positive whole number")
  expect_error(parallel_square(c(1, 2)), "RZIG_NUM_THREADS")
  Sys.unsetenv("RZIG_NUM_THREADS")
  Sys.setenv("_R_CHECK_LIMIT_CORES_" = "TRUE")
  expect_lte(parallel_thread_count(1000L), 2L)
  Sys.setenv("_R_CHECK_LIMIT_CORES_" = "false", OMP_THREAD_LIMIT = "1")
  expect_identical(parallel_thread_count(1000L), 1L)
})

with_threads <- function(threads, code) {
  old <- Sys.getenv("RZIG_NUM_THREADS", unset = NA)
  Sys.setenv(RZIG_NUM_THREADS = threads)
  on.exit(if (is.na(old)) Sys.unsetenv("RZIG_NUM_THREADS") else Sys.setenv(RZIG_NUM_THREADS = old))
  force(code)
}

test_that("parallelReduce gives the same sum for every number of threads", {
  set.seed(3)
  values <- rnorm(100000)
  one <- with_threads("1", parallel_sum(values))
  two <- with_threads("2", parallel_sum(values))
  many <- with_threads("8", parallel_sum(values))
  expect_identical(one, two)
  expect_identical(one, many)
  expect_equal(one, sum(values), tolerance = 1e-10)
  expect_identical(parallel_sum(numeric()), 0)
})

test_that("random streams follow set.seed() and not the number of threads", {
  set.seed(11)
  first <- with_threads("1", parallel_uniforms(500L))
  set.seed(11)
  second <- with_threads("4", parallel_uniforms(500L))
  expect_identical(first, second)
  expect_true(all(first > 0 & first < 1))
  set.seed(12)
  expect_false(identical(parallel_uniforms(500L), first))
  expect_lt(abs(mean(first) - 0.5), 0.05)
})

test_that("a panic on a worker becomes an R error and the session continues", {
  expect_error(parallel_out_of_bounds(as.numeric(1:1000)), "a parallel worker failed and its work was abandoned: index out of bounds")
  expect_identical(parallel_sum(c(1, 2, 3)), 6)
  expect_identical(parallel_count(1000), 1000)
})
