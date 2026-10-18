fr <- function(x) 100 * (x[2] - x[1] * x[1])^2 + (1 - x[1])^2
grr <- function(x) c(-400 * x[1] * (x[2] - x[1] * x[1]) - 2 * (1 - x[1]), 200 * (x[2] - x[1] * x[1]))

test_that("R functions are called with positional and named arguments", {
  expect_identical(call_numeric(function(x) x * 2, c(1, 2)), c(2, 4))
  expect_identical(call_numeric(sqrt, c(4, 9)), c(2, 3))
  expect_identical(call_named(function(x, na.rm) sum(x, na.rm = na.rm), c(1, NA, 3)), 4)
  expect_identical(call_literals(function(...) list(...)), list(2L, 2.5, "text", TRUE))
  expect_identical(call_with_function(function(g) g(3), function(y) y + 1), 4)
  expect_identical(call_optional(NULL), -1)
  expect_identical(call_optional(function() 7), 7)
})

test_that("R objects reach the function unevaluated", {
  formula <- y ~ x
  got <- call_with_object(function(object) object, formula)
  expect_identical(got, formula)
  expect_identical(environment(got), environment(formula))
  expect_identical(call_with_object(function(object) object, quote(a + b)), quote(a + b))
  expect_identical(call_with_object(function(object) object, as.name("zz")), as.name("zz"))
})

test_that("results are converted like arguments, and messages name the function", {
  expect_error(call_numeric(function(x) "a", 1), "the result of `f` must be a numeric vector; got character")
  expect_error(call_numeric(1, 1), "argument `f` of call_numeric must be a function; got double")
  calls <- NULL
  tryCatch(call_numeric(function(x) stop("boom"), 1), error = function(e) calls <<- conditionCall(e))
  expect_identical(calls, quote(f(1)))
})

test_that("R errors keep their class and the Zig frames run their cleanup", {
  before <- call_cleanups()
  custom <- structure(class = c("custom_error", "error", "condition"), list(message = "custom failure", call = NULL))
  condition <- tryCatch(call_with_cleanup(function() stop(custom)), custom_error = function(e) e)
  expect_s3_class(condition, "custom_error")
  expect_identical(conditionMessage(condition), "custom failure")
  expect_error(call_with_cleanup(function() stop("plain failure")), "plain failure")
  expect_identical(call_cleanups(), before + 2)
})

test_that("handlers, restarts and returns outside the call pass the Zig frames", {
  before <- call_cleanups()
  expect_identical(tryCatch(call_with_cleanup(function() warning("w")), warning = function(w) "caught"), "caught")
  muffled <- withCallingHandlers(
    call_with_cleanup(function() {
      warning("w")
      2
    }),
    warning = function(w) invokeRestart("muffleWarning")
  )
  expect_identical(muffled, 1)
  expect_identical(tryCatch(call_with_cleanup(function() message("m")), message = function(m) "message"), "message")
  custom <- structure(class = c("custom", "condition"), list(message = "c", call = NULL))
  expect_identical(tryCatch(call_with_cleanup(function() signalCondition(custom)), custom = function(cnd) "custom"), "custom")
  expect_identical(withRestarts(call_with_cleanup(function() invokeRestart("leave", 5)), leave = function(v) v * 2), 10)
  # Forcing the promise returns from outer(), past the Zig frames.
  outer <- function() {
    delayedAssign("leave", return(9))
    call_with_cleanup(function() leave)
    0
  }
  expect_identical(outer(), 9)
  expect_identical(call_cleanups(), before + 6)
})

test_that("a handled failure is discarded and a raised error replaces it", {
  expect_identical(tryCatch(call_or_default(function() stop("handled"), 5), error = function(e) "outer"), 5)
  expect_identical(call_or_default(function() 3, 5), 3)
  replaced <- tryCatch(call_or_raise(function() stop("original")), error = function(e) conditionMessage(e))
  expect_identical(replaced, "replaced the error of f")
})

test_that("R functions can call functions of rzig packages", {
  expect_identical(call_numeric(function(x) parallel_sum(x) * c(1, 2), c(1, 2, 3)), c(6, 12))
  before <- call_cleanups()
  expect_error(call_with_cleanup(function() call_numeric(function(x) stop("inner"), 1)), "inner")
  expect_error(call_with_cleanup(function() optim_failing(3)), "the objective failed at x = 3")
  expect_identical(call_cleanups(), before + 2)
})

test_that("queued warnings come before the warnings of the R function", {
  seen <- character()
  withCallingHandlers(
    warn_then_call(function() warning("from R")),
    warning = function(w) {
      seen <<- c(seen, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_identical(seen, c("queued before the call", "from R", "queued after the call"))
})

test_that("R's random-number state passes between Zig and R", {
  set.seed(42)
  got <- rng_around_call(function() runif(1))
  set.seed(42)
  expect_identical(got, runif(3))
})

test_that("the optimizers minimize R functions as optim() does", {
  for (method in c("BFGS", "Nelder-Mead", "CG", "L-BFGS-B")) {
    ours <- optim_r(fr, NULL, c(-1.2, 1), method)
    theirs <- optim(c(-1.2, 1), fr, method = method)
    expect_equal(ours$par, theirs$par, tolerance = 1e-10, info = method)
    expect_identical(ours$fn_count, unname(theirs$counts[[1L]]), info = method)
  }
  ours <- optim_r(fr, grr, c(-1.2, 1), "BFGS")
  theirs <- optim(c(-1.2, 1), fr, grr, method = "BFGS")
  expect_equal(ours$par, theirs$par, tolerance = 1e-10)
  expect_identical(ours$gr_count, unname(theirs$counts[[2L]]))
})

test_that("an R error in an objective or integrand ends the routine", {
  expect_error(optim_r(function(x) stop("bad objective"), NULL, c(1, 1), "BFGS"), "bad objective")
  for (method in c("BFGS", "Nelder-Mead", "CG", "L-BFGS-B")) {
    count <- 0
    failing <- function(x) {
      count <<- count + 1
      if (count > 5) stop("stopped after five")
      sum(x^2)
    }
    expect_error(optim_r(failing, NULL, c(1, 1), method), "stopped after five", info = method)
  }
  expect_error(optim_r(fr, function(x) 1, c(1, 1), "BFGS"), "the gradient has 1 values for 2 parameters")
  expect_equal(integrate_r(dnorm, -1.96, 1.96), integrate(dnorm, -1.96, 1.96)$value, tolerance = 1e-12)
  expect_equal(integrate_r(function(x) exp(-x), 0, Inf), 1, tolerance = 1e-8)
  expect_error(integrate_r(function(x) if (x > 0.5) stop("integrand failed") else x, 0, 1), "integrand failed")
  expect_identical(call_numeric(function(x) x, 1), 1)
})
