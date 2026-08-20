test_that("pure Zig work can run in parallel without exposing R", {
  values <- as.numeric(seq_len(10000L))
  expect_identical(parallel_square(values), values * values)
  expect_identical(parallel_square(numeric()), numeric())
})
