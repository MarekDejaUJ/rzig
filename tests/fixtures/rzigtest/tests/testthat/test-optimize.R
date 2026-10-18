fr <- function(x) 100 * (x[2] - x[1] * x[1])^2 + (1 - x[1])^2
grr <- function(x) c(-400 * x[1] * (x[2] - x[1] * x[1]) - 2 * (1 - x[1]), 200 * (x[2] - x[1] * x[1]))

test_that("the optimizers reach the results of optim()", {
  for (method in c("BFGS", "Nelder-Mead", "CG", "L-BFGS-B")) {
    for (with_gradient in c(FALSE, TRUE)) {
      if (method == "Nelder-Mead" && with_gradient) next
      ours <- optim_rosenbrock(method, c(-1.2, 1), with_gradient, NULL, NULL)
      theirs <- optim(c(-1.2, 1), fr, if (with_gradient) grr, method = method)
      info <- paste(method, with_gradient)
      expect_equal(ours$par, theirs$par, tolerance = 1e-10, info = info)
      expect_equal(ours$value, theirs$value, tolerance = 1e-10, info = info)
      expect_identical(ours$fn_count, unname(theirs$counts[[1L]]), info = info)
      expect_identical(ours$convergence, theirs$convergence, info = info)
    }
  }
  bounded <- optim_rosenbrock("L-BFGS-B", c(-1.2, 1), FALSE, c(-2, -2), c(0.5, 2))
  theirs <- optim(c(-1.2, 1), fr, method = "L-BFGS-B", lower = c(-2, -2), upper = c(0.5, 2))
  expect_equal(bounded$par, theirs$par, tolerance = 1e-8)
  expect_lte(bounded$par[[1L]], 0.5)
})

test_that("errors of the objective end the optimization", {
  expect_error(optim_failing(3), "the objective failed at x = 3")
  expect_error(optim_failing(0), "the objective failed")
  expect_error(optim_rosenbrock("BFGS", c(1, 2, 3), FALSE, NULL, NULL), NA)
  expect_error(optim_rosenbrock("L-BFGS-B", c(1, 2), FALSE, c(0, 0, 0), NULL), "3 values for 2 parameters")
})

test_that("integration matches integrate() on finite and infinite ranges", {
  for (limits in list(c(-1, 2), c(-Inf, 0.5), c(1, Inf), c(-Inf, Inf))) {
    ours <- integrate_gaussian(1, 2, limits[[1L]], limits[[2L]])
    theirs <- integrate(dnorm, limits[[1L]], limits[[2L]], mean = 1, sd = 2)
    expect_equal(ours$value, theirs$value, tolerance = 1e-10, info = paste(limits, collapse = " "))
    expect_equal(ours$value, pnorm(limits[[2L]], 1, 2) - pnorm(limits[[1L]], 1, 2), tolerance = 1e-8)
  }
  expect_error(integrate_inverse(-1, 1), "divergent|non-finite|not finite|roundoff|bad integrand")
  # QUADPACK never evaluates 1/x at 0; it runs out of subdivisions.
  expect_error(integrate_inverse(0, 1), "subdivisions|divergent")
})
