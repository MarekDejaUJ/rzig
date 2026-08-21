chain_data <- function(n = 256L) {
  u1 <- rep(c(-1, 1), length.out = n)
  u2 <- rep(c(-1, -1, 1, 1), length.out = n)
  u3 <- rep(c(-1, -1, -1, -1, 1, 1, 1, 1), length.out = n)
  x <- u1
  z <- x + 0.7 * u2
  y <- z + 0.7 * u3
  unname(cbind(x, z, y))
}

expect_native_error <- function(call, pattern, recovery_data) {
  condition <- tryCatch(call(), error = identity)
  stopifnot(
    inherits(condition, "error"),
    grepl(pattern, conditionMessage(condition), fixed = TRUE)
  )

  recovered <- correlation_matrix(recovery_data)
  stopifnot(max(abs(recovered - stats::cor(recovery_data))) < 1e-12)
}

run_gc_stress <- function(iterations = 25L) {
  library(rzigcausal)
  message("gctorture ON - exercising native success and error exits")
  gctorture(TRUE)
  on.exit(gctorture(FALSE), add = TRUE)

  expected_skeleton <- matrix(
    c(FALSE, TRUE, FALSE, TRUE, FALSE, TRUE, FALSE, TRUE, FALSE),
    3L
  )
  for (iteration in seq_len(iterations)) {
    data <- chain_data()
    observed <- correlation_matrix(data)
    stopifnot(
      max(abs(observed - stats::cor(data))) < 1e-12,
      identical(pc_skeleton(data, 0.05, 1L), expected_skeleton)
    )

    non_finite <- data
    non_finite[5L, 2L] <- Inf
    expect_native_error(
      function() correlation_matrix(non_finite),
      "must contain only finite values",
      data
    )
    expect_native_error(
      function() correlation_matrix(matrix(1:12, nrow = 4L)),
      "must store double values",
      data
    )
    expect_native_error(
      function() pc_skeleton(data, 0.05, 6L),
      "limit of 5",
      data
    )
  }

  message("gctorture OK - ", iterations, " success/error iterations")
}

run_gc_stress()
