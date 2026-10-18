test_that("named lists are read into structs with defaults", {
  filled <- record_options(list(tolerance = 0.5))
  expect_identical(filled, list(tolerance = 0.5, max.iter = 100L, method = "newton", weights = NULL))
  full <- record_options(list(method = "bfgs", weights = c(1, 2), max.iter = 7L))
  expect_identical(full$method, "bfgs")
  expect_identical(full$max.iter, 7L)
  expect_identical(full$weights, c(1, 2))
  expect_warning(record_options(list(tolerance = 1, maxiter = 3L)), "unknown entry `maxiter`")
  expect_identical(record_options(list()), record_options(list(tolerance = 1e-8)))
  expect_error(record_options(list(tolerance = "a")), "entry `tolerance`")
  expect_error(record_options(1), "named list")
  expect_error(record_options(list(1, 2)), "no names")
})

test_that("data frames are read column by column and returned as data frames", {
  data <- data.frame(value = c(1, 2, 3, 10), group = factor(c("a", "b", "a", NA), levels = c("a", "b", "c")),
    other = letters[1:4])
  result <- frame_group_means(data)
  expect_s3_class(result, "data.frame")
  expect_identical(result$group, c("a", "b", "c"))
  expect_identical(result$mean, c(2, 2, NA))
  expect_identical(result$n, c(2L, 1L, 0L))
  expect_identical(nrow(result), 3L)
  expect_identical(rownames(result), c("1", "2", "3"))
  expect_error(frame_group_means(list(value = 1, group = factor("a"))), "data frame")
  expect_error(frame_group_means(data.frame(value = 1)), "no column `group`")
  expect_error(frame_group_means(data.frame(value = 1, group = 1L)), "factor()", fixed = TRUE)
})

test_that("factors are read and returned with their levels", {
  values <- factor(c("low", "high", NA, "low"), levels = c("low", "high"))
  reversed <- factor_reverse_levels(values)
  expect_identical(levels(reversed), c("high", "low"))
  expect_identical(as.character(reversed), as.character(values))
  expect_error(factor_reverse_levels(c("low", "high")), "factor()", fixed = TRUE)
  broken <- structure(c(1L, 5L), levels = c("a", "b"), class = "factor")
  expect_error(factor_reverse_levels(broken), "code 5 at position 2")
})

test_that("optional vectors accept NULL", {
  expect_identical(optional_length(NULL), -1L)
  expect_identical(optional_length(c(1, 2, 3)), 3L)
  expect_error(optional_length("a"), "numeric vector")
})
