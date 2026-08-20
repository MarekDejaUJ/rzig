test_that("parallel correlations agree with base R", {
  data <- chain_data()
  original <- data
  observed <- correlation_matrix(data)

  expect_equal(observed, unname(stats::cor(data)), tolerance = 1e-12)
  expect_equal(observed, t(observed), tolerance = 0)
  expect_identical(diag(observed), rep(1, ncol(data)))
  expect_identical(data, original)
})

test_that("correlation handles a larger pure-compute workload", {
  n <- if (identical(Sys.getenv("RZIG_GC_STRESS"), "true")) 256L else 20000L
  data <- cbind(
    sin(seq_len(n) / 17),
    cos(seq_len(n) / 29),
    sin(seq_len(n) / 17) + cos(seq_len(n) / 29),
    rep(c(-1, 1), length.out = n)
  )
  expect_equal(
    correlation_matrix(data),
    unname(stats::cor(data)),
    tolerance = 1e-11
  )
})
