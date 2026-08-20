test_that("named Zig lists preserve order, names, and value types", {
  expect_identical(
    named_summary(c(1.5, 2.5)),
    list(values = c(1.5, 2.5), count = 2L)
  )
  expect_identical(
    named_summary(numeric()),
    list(values = numeric(), count = 0L)
  )
})
