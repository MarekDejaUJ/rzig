cases <- list(
  normal = list(values = c(1, 2), x = 0.3, p = 0.7,
    d = function(x, log) dnorm(x, 1, 2, log = log), pf = function(x, lower, log) pnorm(x, 1, 2, lower, log),
    qf = function(p, lower, log) qnorm(p, 1, 2, lower, log), r = function(n) rnorm(n, 1, 2)),
  uniform = list(values = c(-1, 3), x = 0.5, p = 0.2,
    d = function(x, log) dunif(x, -1, 3, log), pf = function(x, lower, log) punif(x, -1, 3, lower, log),
    qf = function(p, lower, log) qunif(p, -1, 3, lower, log), r = function(n) runif(n, -1, 3)),
  gamma = list(values = c(2.5, 1.5), x = 3, p = 0.4,
    d = function(x, log) dgamma(x, 2.5, scale = 1.5, log = log),
    pf = function(x, lower, log) pgamma(x, 2.5, scale = 1.5, lower.tail = lower, log.p = log),
    qf = function(p, lower, log) qgamma(p, 2.5, scale = 1.5, lower.tail = lower, log.p = log),
    r = function(n) rgamma(n, 2.5, scale = 1.5)),
  beta = list(values = c(2, 5), x = 0.3, p = 0.6,
    d = function(x, log) dbeta(x, 2, 5, log = log),
    pf = function(x, lower, log) pbeta(x, 2, 5, lower.tail = lower, log.p = log),
    qf = function(p, lower, log) qbeta(p, 2, 5, lower.tail = lower, log.p = log), r = function(n) rbeta(n, 2, 5)),
  binomial = list(values = c(10, 0.3), x = 4, p = 0.5,
    d = function(x, log) dbinom(x, 10, 0.3, log), pf = function(x, lower, log) pbinom(x, 10, 0.3, lower, log),
    qf = function(p, lower, log) qbinom(p, 10, 0.3, lower, log), r = function(n) rbinom(n, 10, 0.3)),
  poisson = list(values = 3.5, x = 2, p = 0.8,
    d = function(x, log) dpois(x, 3.5, log), pf = function(x, lower, log) ppois(x, 3.5, lower, log),
    qf = function(p, lower, log) qpois(p, 3.5, lower, log), r = function(n) rpois(n, 3.5)),
  exponential = list(values = 2, x = 0.7, p = 0.3,
    d = function(x, log) dexp(x, 2, log), pf = function(x, lower, log) pexp(x, 2, lower, log),
    qf = function(p, lower, log) qexp(p, 2, lower, log), r = function(n) rexp(n, 2)),
  t = list(values = 4, x = 1.2, p = 0.9,
    d = function(x, log) dt(x, 4, log = log), pf = function(x, lower, log) pt(x, 4, lower.tail = lower, log.p = log),
    qf = function(p, lower, log) qt(p, 4, lower.tail = lower, log.p = log), r = function(n) rt(n, 4)),
  chisq = list(values = 3, x = 2.2, p = 0.5,
    d = function(x, log) dchisq(x, 3, log = log), pf = function(x, lower, log) pchisq(x, 3, lower.tail = lower, log.p = log),
    qf = function(p, lower, log) qchisq(p, 3, lower.tail = lower, log.p = log), r = function(n) rchisq(n, 3)),
  f = list(values = c(3, 7), x = 1.5, p = 0.25,
    d = function(x, log) df(x, 3, 7, log = log), pf = function(x, lower, log) pf(x, 3, 7, lower.tail = lower, log.p = log),
    qf = function(p, lower, log) qf(p, 3, 7, lower.tail = lower, log.p = log), r = function(n) rf(n, 3, 7)),
  lognormal = list(values = c(0.5, 0.8), x = 1.7, p = 0.6,
    d = function(x, log) dlnorm(x, 0.5, 0.8, log), pf = function(x, lower, log) plnorm(x, 0.5, 0.8, lower, log),
    qf = function(p, lower, log) qlnorm(p, 0.5, 0.8, lower, log), r = function(n) rlnorm(n, 0.5, 0.8)),
  weibull = list(values = c(1.5, 2), x = 1.1, p = 0.45,
    d = function(x, log) dweibull(x, 1.5, 2, log), pf = function(x, lower, log) pweibull(x, 1.5, 2, lower, log),
    qf = function(p, lower, log) qweibull(p, 1.5, 2, lower, log), r = function(n) rweibull(n, 1.5, 2)),
  logistic = list(values = c(1, 0.5), x = 0.4, p = 0.35,
    d = function(x, log) dlogis(x, 1, 0.5, log), pf = function(x, lower, log) plogis(x, 1, 0.5, lower, log),
    qf = function(p, lower, log) qlogis(p, 1, 0.5, lower, log), r = function(n) rlogis(n, 1, 0.5)),
  cauchy = list(values = c(0, 2), x = 1, p = 0.75,
    d = function(x, log) dcauchy(x, 0, 2, log), pf = function(x, lower, log) pcauchy(x, 0, 2, lower, log),
    qf = function(p, lower, log) qcauchy(p, 0, 2, lower, log), r = function(n) rcauchy(n, 0, 2)),
  geometric = list(values = 0.3, x = 2, p = 0.5,
    d = function(x, log) dgeom(x, 0.3, log), pf = function(x, lower, log) pgeom(x, 0.3, lower, log),
    qf = function(p, lower, log) qgeom(p, 0.3, lower, log), r = function(n) rgeom(n, 0.3)),
  hypergeometric = list(values = c(7, 5, 4), x = 2, p = 0.6,
    d = function(x, log) dhyper(x, 7, 5, 4, log), pf = function(x, lower, log) phyper(x, 7, 5, 4, lower, log),
    qf = function(p, lower, log) qhyper(p, 7, 5, 4, lower, log), r = function(n) rhyper(n, 7, 5, 4)),
  negative_binomial = list(values = c(3, 0.4), x = 5, p = 0.3,
    d = function(x, log) dnbinom(x, 3, 0.4, log = log),
    pf = function(x, lower, log) pnbinom(x, 3, 0.4, lower.tail = lower, log.p = log),
    qf = function(p, lower, log) qnbinom(p, 3, 0.4, lower.tail = lower, log.p = log),
    r = function(n) rnbinom(n, 3, 0.4))
)

test_that("densities, distribution functions and quantiles equal R's", {
  for (name in names(cases)) {
    case <- cases[[name]]
    for (log in c(FALSE, TRUE)) {
      expect_identical(rmath_eval("d", name, case$x, case$values, TRUE, log), case$d(case$x, log), info = name)
      for (lower in c(TRUE, FALSE)) {
        expect_identical(rmath_eval("p", name, case$x, case$values, lower, log), case$pf(case$x, lower, log), info = name)
        probability <- if (log) log(case$p) else case$p
        expect_identical(rmath_eval("q", name, probability, case$values, lower, log), case$qf(probability, lower, log),
          info = name)
      }
    }
  }
  expect_true(is.nan(rmath_eval("d", "gamma", 1, c(-1, 1), TRUE, FALSE)))
  expect_error(rmath_eval("x", "gamma", 1, c(1, 1), TRUE, FALSE), "kind must be")
})

test_that("draws follow set.seed() like R's generators", {
  for (name in names(cases)) {
    case <- cases[[name]]
    set.seed(20261018)
    ours <- rmath_draws(name, 25L, case$values)
    set.seed(20261018)
    expect_identical(ours, as.numeric(case$r(25L)), info = name)
  }
})
