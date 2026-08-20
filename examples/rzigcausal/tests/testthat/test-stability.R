test_that("invalid R values become errors and leave the session usable", {
  expect_error_live(
    function() correlation_matrix(matrix(1:8, nrow = 4L)),
    "must store double values"
  )
  expect_error_live(
    function() correlation_matrix(as.numeric(1:8)),
    "must be a numeric matrix"
  )
  expect_error_live(
    function() correlation_matrix(matrix(as.numeric(1:6), nrow = 3L)),
    "at least four observation rows"
  )
  expect_error_live(
    function() correlation_matrix(matrix(as.numeric(1:8), ncol = 1L)),
    "at least two variable columns"
  )

  non_finite <- chain_data(32L)
  non_finite[5L, 2L] <- Inf
  expect_error_live(
    function() correlation_matrix(non_finite),
    "must contain only finite values"
  )

  constant <- cbind(as.numeric(1:8), rep(1, 8L))
  expect_error_live(
    function() correlation_matrix(constant),
    "column 2 is constant"
  )
})

test_that("PC tuning parameters are bounded before expensive search", {
  data <- chain_data(32L)
  expect_error_live(
    function() pc_skeleton(data, 0, 1L),
    "alpha must be finite"
  )
  expect_error_live(
    function() pc_skeleton(data, 1, 1L),
    "alpha must be finite"
  )
  expect_error_live(
    function() pc_skeleton(data, NA_real_, 1L),
    "cannot be NA"
  )
  expect_error_live(
    function() pc_skeleton(data, 0.05, -1L),
    "must be non-negative"
  )
  expect_error_live(
    function() pc_skeleton(data, 0.05, 6L),
    "limit of 5"
  )
  expect_error_live(
    function() pc_skeleton(chain_data(4L), 0.05, 1L),
    "more than max_depth + 3 rows"
  )
})

test_that("the demonstration rejects unbounded graph size", {
  data <- matrix(as.numeric(seq_len(4L * 65L)), nrow = 4L, ncol = 65L)
  expect_error_live(
    function() correlation_matrix(data),
    "at most 64 variables"
  )
})
