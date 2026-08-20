test_that("mutable inputs duplicate before Zig writes", {
  original <- c(1, 2, 3)
  alias <- original
  result <- scale_in_place(alias, 2)

  expect_identical(result, c(2, 4, 6))
  expect_identical(alias, c(1, 2, 3))
  expect_identical(original, c(1, 2, 3))
})

test_that("empty mutable vectors are supported", {
  expect_identical(scale_in_place(numeric(), 2), numeric())
})

test_that("mutable numeric inputs reject implicit integer conversion", {
  expect_error(scale_in_place(1:3, 2), "use as.numeric\\(\\) in R")
  expect_identical(scale_in_place(c(4, 5), 2), c(8, 10))
})
