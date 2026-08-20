test_that("numeric returns preserve copied names and class", {
  result <- decorate_values(c(1.5, 2.5), c("left", "right"))
  expect_identical(as.numeric(result), c(1.5, 2.5))
  expect_identical(names(result), c("left", "right"))
  expect_identical(class(result), "rzig_values")
  expect_error(decorate_values(c(1, 2), "one"), "names.*length 1")
})

test_that("numeric returns can carry validated dimensions", {
  result <- reshape_values(as.numeric(1:6), 2L)
  expect_identical(result, matrix(as.numeric(1:6), nrow = 2L))
  expect_identical(reshape_values(numeric(), 0L), matrix(numeric(), 0L, 0L))
  expect_error(reshape_values(as.numeric(1:5), 2L), "not divisible")
})

test_that("numeric matrix inputs expose shape and column-major data", {
  expect_identical(matrix_trace(matrix(c(1, 2, 3, 4), 2L)), 5)
  expect_identical(matrix_trace(matrix(numeric(), 0L, 0L)), 0)
  expect_error(matrix_trace(matrix(as.numeric(1:6), 2L)), "must be square")
  expect_error(matrix_trace(c(1, 2, 3, 4)), "without dimensions")
  expect_error(matrix_trace(matrix(1:4, 2L)), "storage.mode")
  expect_identical(matrix_trace(matrix(c(2, 0, 0, 3), 2L)), 5)
})
