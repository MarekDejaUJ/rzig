test_that("ctx.print and ctx.eprint write to R's output and message streams", {
  out <- capture.output(messages <- capture.output(console_lines(3L), type = "message"))
  expect_identical(out, c("line 1", "line 2", "line 3"))
  expect_identical(messages, "printed 3 lines")
  many <- capture.output(summary <- capture.output(console_lines(250L), type = "message"))
  expect_identical(summary, "printed 250 lines")
  expect_length(many, 250L)
  expect_identical(many[[250L]], "line 250")
})

test_that("long output is written in full", {
  out <- capture.output(console_wide(10000L))
  expect_identical(nchar(out), 10000L)
})

test_that("progress bars draw only when asked and end their line", {
  hidden <- capture.output(steps <- progress_steps(50L, FALSE), type = "message")
  expect_identical(steps, 50L)
  expect_length(hidden, 0L)
  shown <- capture.output(invisible(progress_steps(50L, TRUE)), type = "message")
  expect_length(shown, 1L)
  expect_match(shown, "] 100%$")
  zero <- capture.output(invisible(progress_steps(0L, TRUE)), type = "message")
  expect_match(zero, "] 100%$")
})
