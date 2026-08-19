test_that("a numeric vector crosses the R-Zig boundary", {
  expect_equal(add_one(c(1, 2, 3)), c(2, 3, 4))
})
