test_that("logical vectors keep NA in and out", {
  expect_identical(logical_tally(c(TRUE, NA, FALSE, TRUE)), c(2L, 1L, 1L))
  expect_identical(logical_not(c(TRUE, NA, FALSE)), c(FALSE, NA, TRUE))
  expect_identical(logical_not(logical()), logical())
  expect_identical(logical_not(c(a = TRUE)), FALSE)
  expect_error(logical_tally(1:3), "logical vector")
})

test_that("character vectors and optional strings keep NA", {
  expect_identical(upper_or_na(c("ab", NA, "z")), c("AB", NA, "Z"))
  expect_identical(upper_or_na(NA_character_), NA_character_)
  expect_identical(upper_or_na(character()), character())
  expect_identical(label_or_default(NA), "(none)")
  expect_identical(label_or_default(NULL), "(none)")
  expect_identical(label_or_default(NA_character_), "(none)")
  expect_identical(label_or_default("x"), "x")
  expect_error(label_or_default(c("a", "b")), "length 1")
  expect_error(label_or_default(1), "character vector")
})

test_that("NA constants are R's missing values", {
  expect_true(is.na(na_real()))
  expect_false(is.nan(na_real()))
  expect_identical(na_real(), NA_real_)
  expect_identical(na_integer(), NA_integer_)
  expect_identical(na_logical(), NA)
})
