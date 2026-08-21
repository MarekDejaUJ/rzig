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
  permutation <- c(3L, 1L, 2L)
  permuted <- pc_skeleton(data[, permutation], 0.05, 1L)
  restored <- permuted[order(permutation), order(permutation), drop = FALSE]

  expect_identical(restored, expected)
})
