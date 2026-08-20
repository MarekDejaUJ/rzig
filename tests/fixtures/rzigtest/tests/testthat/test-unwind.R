native_unwind_call <- function(name, ...) {
  symbol <- get(paste0("C_", name), envir = asNamespace("rzigtest"))
  .Call(symbol, ...)
}

test_that("R unwind cleanup runs on ordinary and non-local returns", {
  before <- native_unwind_call("unwind_cleanup_count")
  expect_identical(native_unwind_call("unwind_cleanup_normal"), before + 1L)
  expect_error(native_unwind_call("unwind_cleanup_error"))
  expect_identical(native_unwind_call("unwind_cleanup_count"), before + 2L)
  expect_identical(add_one(c(4, 8)), c(5, 9))
})
