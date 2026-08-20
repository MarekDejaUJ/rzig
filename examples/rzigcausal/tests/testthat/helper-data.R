chain_data <- function(
  n = if (identical(Sys.getenv("RZIG_GC_STRESS"), "true")) 256L else 4096L
) {
  u1 <- rep(c(-1, 1), length.out = n)
  u2 <- rep(c(-1, -1, 1, 1), length.out = n)
  u3 <- rep(c(-1, -1, -1, -1, 1, 1, 1, 1), length.out = n)
  x <- u1
  z <- x + 0.7 * u2
  y <- z + 0.7 * u3
  cbind(x, z, y)
}

expect_error_live <- function(call, pattern) {
  condition <- tryCatch(call(), error = identity)
  expect_s3_class(condition, "error")
  expect_match(conditionMessage(condition), pattern, fixed = TRUE)
  data <- unname(chain_data(32L))
  expect_equal(correlation_matrix(data), stats::cor(data), tolerance = 1e-12)
  invisible(condition)
}
