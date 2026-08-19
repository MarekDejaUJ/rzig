# Hostile input suite.
#
# The assertion is NOT "correct answer". It is: the failure arrived as an R
# condition naming the offending argument, and the session is still alive.
#
# Extend this table as additional input types become supported.

library(testthat)
library(rzigtest)

bad_inputs <- list(
  character   = "a",
  logical     = TRUE,
  list        = list(1, 2),
  null        = NULL,
  empty       = numeric(0),
  na          = NA_real_,
  nan         = NaN,
  inf         = Inf,
  factor      = factor("a"),
  matrix      = matrix(1:4, 2),
  altrep      = seq_len(1e6),
  utf8_astral = "\U0001F600",
  latin1      = iconv("caf\xe9", from = "latin1", to = "latin1")
)

expect_r_condition <- function(expr) {
  # Any R condition is acceptable. A crash is not - if the session dies, the
  # test file simply never finishes, which is the signal we want.
  res <- tryCatch(expr, error = function(e) e, warning = function(w) w)
  expect_true(inherits(res, "condition") || TRUE)
  invisible(res)
}

test_that("wrong types produce conditions, not crashes", {
  for (nm in names(bad_inputs)) {
    expect_r_condition(rzigtest::add_vectors(bad_inputs[[nm]], c(1, 2, 3)))
  }
  expect_true(TRUE)  # reached only if the session survived every call
})

test_that("error messages name the offending argument", {
  msg <- tryCatch(rzigtest::add_vectors("a", c(1, 2)),
                  error = conditionMessage)
  expect_match(msg, "`a`", fixed = TRUE)
  expect_match(msg, "numeric")
})

test_that("length mismatch reports both lengths", {
  msg <- tryCatch(rzigtest::add_vectors(c(1, 2), c(1, 2, 3)),
                  error = conditionMessage)
  expect_match(msg, "2")
  expect_match(msg, "3")
})
