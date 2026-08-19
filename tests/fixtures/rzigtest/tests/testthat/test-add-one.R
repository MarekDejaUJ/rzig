test_that("a numeric vector crosses the R-Zig boundary", {
  expect_equal(add_one(c(1, 2, 3)), c(2, 3, 4))
})

test_that("a Zig safety panic becomes an R error and the session survives", {
  skip_if(
    identical(Sys.getenv("RZIG_RUNNING_UNDER_VALGRIND"), "true"),
    "Valgrind cannot resume from an intentional Zig safety trap"
  )
  expect_error(panic_bounds(), "index out of bounds")
  expect_equal(add_one(c(4, 5)), c(5, 6))
})

test_that("Zig allocations are released during an R error", {
  for (iteration in seq_len(8)) {
    expect_error(allocate_then_error(), "intentional error")
  }
  expect_equal(add_one(c(8, 13)), c(9, 14))
})
