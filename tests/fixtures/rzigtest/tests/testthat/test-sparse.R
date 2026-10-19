test_that("sparse matrices are read through their slots", {
  skip_if_not_installed("Matrix")
  set.seed(7)
  m <- Matrix::rsparsematrix(30, 12, density = 0.2)
  expect_s4_class(m, "dgCMatrix")
  expect_equal(csc_column_sums(m), Matrix::colSums(m), tolerance = 1e-12)
  x <- rnorm(12)
  expect_equal(csc_times_vector(m, x), as.numeric(m %*% x), tolerance = 1e-12)
  empty <- Matrix::sparseMatrix(i = integer(), j = integer(), x = numeric(), dims = c(3L, 2L))
  expect_identical(csc_column_sums(empty), c(0, 0))
  expect_error(csc_column_sums(as.matrix(m)), "dgCMatrix")
  expect_error(csc_column_sums(Matrix::forceSymmetric(crossprod(m))), "generalMatrix")
  broken <- m
  broken@i[[1L]] <- 99L
  expect_error(csc_column_sums(broken), "outside the matrix")
  unsorted <- Matrix::sparseMatrix(i = c(1L, 2L), j = c(1L, 1L), x = c(1, 2), dims = c(2L, 1L))
  unsorted@i <- rev(unsorted@i)
  expect_error(csc_column_sums(unsorted), "must increase")
})
