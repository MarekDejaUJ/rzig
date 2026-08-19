native_call <- function(name, ...) {
  symbol <- get(paste0("C_", name), envir = asNamespace("rzigtest"))
  .Call(symbol, ...)
}

test_that("generated wrappers cover representative arities", {
  expect_identical(native_call("arity_zero"), 0L)
  expect_identical(native_call("echo_i32", 7L), 7L)
  expect_identical(native_call("sum_three", 1, 2, 3), 6)
  expect_identical(
    native_call("sum_eight", 1, 2, 3, 4, 5, 6, 7, 8),
    36
  )
})
