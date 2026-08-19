test_that("Zig and R agree on variadic string and integer arguments", {
  symbol <- get("C_ucrt_smoke", envir = asNamespace("rzigtest"))
  output <- capture.output(result <- .Call(symbol, 37L))

  expect_identical(result, 37L)
  expect_identical(output, "rzig-ucrt 37")
})
