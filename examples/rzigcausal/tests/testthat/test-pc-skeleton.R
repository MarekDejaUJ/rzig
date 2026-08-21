test_that("conditioning removes the chain's marginal end-to-end edge", {
  data <- chain_data()
  complete <- pc_skeleton(data, 0.05, 0L)
  skeleton <- pc_skeleton(data, 0.05, 1L)

  expect_identical(complete, matrix(c(FALSE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, FALSE), 3L))
  expect_identical(skeleton, matrix(c(FALSE, TRUE, FALSE, TRUE, FALSE, TRUE, FALSE, TRUE, FALSE), 3L))
})

test_that("the depth-frozen skeleton is stable under variable order", {
  data <- chain_data()
  expected <- pc_skeleton(data, 0.05, 1L)
  permutations <- rbind(
    c(1L, 2L, 3L),
    c(1L, 3L, 2L),
    c(2L, 1L, 3L),
    c(2L, 3L, 1L),
    c(3L, 1L, 2L),
    c(3L, 2L, 1L)
  )

  for (row in seq_len(nrow(permutations))) {
    permutation <- permutations[row, ]
    permuted <- pc_skeleton(data[, permutation], 0.05, 1L)
    restored <- permuted[order(permutation), order(permutation), drop = FALSE]

    expect_identical(restored, expected, info = paste("permutation", row))
  }
})

test_that("a mid-size graph exercises conditioning depths through five", {
  data <- dense_gaussian_data()
  # The permissive alpha keeps this factor graph dense so every depth is
  # eligible; this is a mechanical search-path test, not a calibration claim.
  observed <- pc_skeleton(data, 0.95, 5L)
  expected <- matrix(TRUE, ncol(data), ncol(data))
  diag(expected) <- FALSE

  expect_identical(observed, expected)
  expect_identical(observed, t(observed))

  permutation <- c(12L, 1L, 7L, 2L, 8L, 3L, 9L, 4L, 10L, 5L, 11L, 6L)
  permuted <- pc_skeleton(data[, permutation], 0.95, 5L)
  restored <- permuted[order(permutation), order(permutation), drop = FALSE]

  expect_identical(restored, expected)
})
