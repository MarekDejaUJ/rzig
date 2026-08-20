test_that("interrupt checks return normally when no interrupt is pending", {
  expect_identical(interruptible_count(0L), 0L)
  expect_identical(interruptible_count(250000L), 250000L)
})
