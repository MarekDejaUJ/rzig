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

test_that("integer and logical matrices are read column by column", {
  values <- matrix(c(1L, NA, 3L, 4L), 2L)
  expect_identical(int_matrix_sum(matrix(1:6, 2L)), 21)
  # NA_integer_ reaches Zig as std.math.minInt(i32).
  expect_identical(int_matrix_sum(values), 1 - 2147483648 + 3 + 4)
  expect_identical(bool_matrix_row_counts(matrix(c(TRUE, FALSE, TRUE, TRUE), 2L)), c(2L, 1L))
  expect_identical(bool_matrix_row_counts(matrix(logical(), 0L, 3L)), integer())
  expect_error(bool_matrix_row_counts(matrix(c(TRUE, NA), 1L)), "found NA at position 2")
  expect_error(int_matrix_sum(matrix(c(1, 2), 1L)), "storage.mode(x) <- \"integer\"", fixed = TRUE)
  expect_error(bool_matrix_row_counts(matrix(1:2, 1L)), "storage.mode(x) <- \"logical\"", fixed = TRUE)
  expect_error(int_matrix_sum(1:4), "an integer vector without dimensions", fixed = TRUE)
})

test_that("mutable matrices and integer vectors change a duplicate that keeps attributes", {
  original <- matrix(c(1, 2, 3, 4), 2L, dimnames = list(c("a", "b"), c("x", "y")))
  copy <- original
  changed <- matrix_add_column_index(original, 10)
  expect_identical(original, copy)
  expect_identical(unname(changed), matrix(c(1, 2, 13, 14), 2L))
  expect_identical(dimnames(changed), dimnames(original))

  counts <- matrix(1:4, 2L)
  flipped <- int_matrix_negate_diagonal(counts)
  expect_identical(counts, matrix(1:4, 2L))
  expect_identical(flipped, matrix(c(-1L, 2L, 3L, -4L), 2L))

  vector <- c(first = 1L, second = 2L)
  expect_identical(int_add_in_place(vector, 5L), c(first = 6L, second = 7L))
  expect_identical(vector, c(first = 1L, second = 2L))
  expect_error(int_add_in_place(.Machine$integer.max, 1L), "integer overflow")
  expect_error(int_add_in_place(c(1, 2), 1L), "as.integer()", fixed = TRUE)
  expect_error(matrix_add_column_index(1:4, 1), "without dimensions")
})

test_that("matrix returns carry dimnames", {
  result <- named_matrix(2L, 3L, c("r1", "r2"), c("a", "b", "c"))
  expect_identical(result, matrix(c(1, 4, 2, 5, 3, 6), 2L, dimnames = list(c("r1", "r2"), c("a", "b", "c"))))
  unnamed_rows <- named_matrix(2L, 1L, character(), "only")
  expect_identical(dimnames(unnamed_rows), list(NULL, "only"))
  expect_identical(dimnames(named_matrix(1L, 1L, character(), character())), NULL)
  expect_error(named_matrix(2L, 2L, "r1", character()), "1 row names for 2 rows")
  expect_error(named_matrix(1L, 2L, character(), c("a", "b", "c")), "3 column names for 2 columns")
})
