# GC stress for R functions called from Zig (rzig.Function): with gctorture,
# every allocation of the boundary and of the R code collects garbage, so an
# unprotected object of the call path fails here.
#
# Usage: Rscript tools/gctorture_run.R tests/gctorture-callbacks.R
library(rzigtest)

stopifnot(identical(call_numeric(function(x) x * 2, c(1, 2, 3)), c(2, 4, 6)))
stopifnot(identical(call_named(function(x, na.rm) sum(x, na.rm = na.rm), c(1, NA, 3)), 4))
stopifnot(identical(call_literals(function(...) list(...)), list(2L, 2.5, "text", TRUE)))
formula <- y ~ x
stopifnot(identical(call_with_object(function(object) object, formula), formula))
stopifnot(identical(tryCatch(call_with_cleanup(function() stop("boom")), error = conditionMessage), "boom"))
stopifnot(identical(tryCatch(call_with_cleanup(function() warning("w")), warning = function(w) "caught"), "caught"))
stopifnot(identical(call_numeric(function(x) call_numeric(function(y) y + 1, x), 1), 2))
set.seed(1)
drawn <- rng_around_call(function() runif(1))
set.seed(1)
stopifnot(identical(drawn, runif(3)))
rosenbrock <- function(x) 100 * (x[2] - x[1] * x[1])^2 + (1 - x[1])^2
fit <- optim_r(rosenbrock, NULL, c(-1.2, 1), "Nelder-Mead")
stopifnot(abs(fit$par[[1L]] - 1) < 0.01)
stopifnot(abs(integrate_r(dnorm, -1, 1) - (pnorm(1) - pnorm(-1))) < 1e-8)
cat("R functions called from Zig pass the GC stress\n")
