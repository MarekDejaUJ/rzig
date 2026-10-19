# Numerical routines of R in Zig code

Zig code in an R package can use the numerical routines that R itself
uses: the distributions of R’s maths library, the BLAS and LAPACK that R
links, the optimizers of
[`optim()`](https://rdrr.io/r/stats/optim.html), the integration of
[`integrate()`](https://rdrr.io/r/stats/integrate.html), and R functions
passed as arguments. Each routine runs with R’s errors turned into
errors of the Zig call, so the Zig code returns them and R reports them
after the Zig frames have returned. The package below uses each of them;
the build and the calls run when a supported Zig compiler is found (this
copy ran them).

``` r

path <- file.path(tempdir(), "numericspkg")
create_rzig_package(path, tests = FALSE)
#> Created package numericspkg at /tmp/Rtmp6ulCiq/numericspkg
#> Write Zig functions in src/rzig/src/main.zig, then run rzig::document(path) and rzig::build_zig(path)
main_zig <- file.path(path, "src", "rzig", "src", "main.zig")
use_rzig_lapack(path)
#> Package numericspkg links the LAPACK and BLAS of R
```

[`use_rzig_lapack()`](https://marekdejauj.github.io/rzig/reference/use_rzig_lapack.md)
asks `configure` to link LAPACK, BLAS and the Fortran runtime, as
*Writing R Extensions* prescribes.

## Distributions

`rzig.Rmath` evaluates the density, the distribution function and the
quantile function of R’s distributions with R’s parameter names and
defaults:

``` r

cat(
  "",
  "/// The upper tail of a gamma distribution with shape 2.",
  "/// @param x Quantiles.",
  "/// @return Probabilities.",
  "/// @export",
  "pub fn gamma_upper(ctx: *rzig.Ctx, x: []const f64) rzig.Error![]f64 {",
  "    const out = try ctx.alloc(f64, x.len);",
  "    for (x, out) |value, *slot| {",
  "        slot.* = try rzig.Rmath.cdf(.gamma, value, .{ .shape = 2 }, .{ .lower_tail = false });",
  "    }",
  "    return out;",
  "}",
  sep = "\n", file = main_zig, append = TRUE
)
```

## Linear algebra

`rzig.Blas` and `rzig.Lapack` call R’s BLAS and LAPACK on column-major
matrices and check the shapes before each call. A Cholesky solve:

``` r

cat(
  "",
  "/// Solve a symmetric positive-definite system with a Cholesky factor.",
  "/// @param a A symmetric positive-definite matrix.",
  "/// @param b A right-hand side.",
  "/// @return The solution.",
  "/// @export",
  "pub fn chol_solve(ctx: *rzig.Ctx, a: rzig.Matrix, b: []const f64) rzig.Error![]f64 {",
  "    const factor = try ctx.matrix(a.nrow, a.ncol);",
  "    @memcpy(factor.data, a.data);",
  "    try rzig.Lapack.potrf(ctx, .upper, factor);",
  "    const x = try ctx.matrix(b.len, 1);",
  "    @memcpy(x.data, b);",
  "    try rzig.Lapack.potrs(ctx, .upper, factor.view(), x);",
  "    return x.data;",
  "}",
  sep = "\n", file = main_zig, append = TRUE
)
```

A matrix that is not positive definite is an R error with LAPACK’s
reason.

## Optimization and R functions as arguments

`rzig.Optimize.minimize` runs the optimizers of
[`optim()`](https://rdrr.io/r/stats/optim.html) on a problem with a
`value` method and, optionally, a `gradient` method; without one, it
uses the central differences of
[`optim()`](https://rdrr.io/r/stats/optim.html). An `rzig.Function`
argument receives an R function, and its `call` method evaluates it, so
the objective can be written in R:

``` r

cat(
  "",
  "const RObjective = struct {",
  "    ctx: *rzig.Ctx,",
  "    objective: rzig.Function,",
  "",
  "    pub fn value(self: *const RObjective, x: []const f64) rzig.Error!f64 {",
  "        return self.objective.call(self.ctx, f64, .{x});",
  "    }",
  "};",
  "",
  "/// Minimize an R function with BFGS.",
  "/// @param f An R function of a numeric vector.",
  "/// @param start Starting values.",
  "/// @return The minimizer.",
  "/// @export",
  "pub fn minimize_r(ctx: *rzig.Ctx, f: rzig.Function, start: []const f64) rzig.Error![]f64 {",
  "    const x = try ctx.dupe(f64, start);",
  "    _ = try rzig.Optimize.minimize(ctx, .bfgs, &RObjective{ .ctx = ctx, .objective = f }, x, .{});",
  "    return x;",
  "}",
  sep = "\n", file = main_zig, append = TRUE
)
```

An R error in the objective stops the optimizer and reaches R unchanged,
with its class, after the Zig frames have run their `defer` blocks.

## Integration

`rzig.Integrate.integrate` integrates a Zig function as
[`integrate()`](https://rdrr.io/r/stats/integrate.html) does, also over
infinite ranges:

``` r
cat(
  "",
  "const Exponential = struct {",
  "    rate: f64,",
  "",
  "    pub fn value(self: *const Exponential, x: f64) f64 {",
  "        return self.rate * @exp(-self.rate * x);",
  "    }",
  "};",
  "",
  "/// The probability of an exponential variable between two limits.",
  "/// @param rate The rate.",
  "/// @param lower,upper The limits.",
  "/// @return A probability.",
  "/// @export",
  "pub fn exponential_mass(ctx: *rzig.Ctx, rate: f64, lower: f64, upper: f64) rzig.Error!f64 {",
  "    const result = try rzig.Integrate.integrate(ctx, &Exponential{ .rate = rate }, lower, upper, .{});",
  "    return result.value;",
  "}",
  sep = "\n", file = main_zig, append = TRUE
)
document(path)
Generated RZig bindings for numericspkg: 5 exported functions
```

## Build and run

``` r

build <- build_zig(path)
library(build$package, character.only = TRUE, lib.loc = build$library)
all.equal(gamma_upper(c(0.5, 2)), pgamma(c(0.5, 2), shape = 2, lower.tail = FALSE))
#> [1] TRUE
a <- crossprod(matrix(c(2, 1, 0, 1, 3, 1, 0, 1, 4), 3)) + diag(3)
all.equal(chol_solve(a, c(1, 2, 3)), solve(a, c(1, 2, 3)))
#> [1] TRUE
try(chol_solve(matrix(c(1, 2, 2, 1), 2), c(1, 1)))
#> Error : rzig: potrf: the matrix is not positive definite (leading minor 2)
rosenbrock <- function(x) 100 * (x[2] - x[1]^2)^2 + (1 - x[1])^2
minimize_r(rosenbrock, c(-1.2, 1))
#> [1] 0.9998044 0.9996084
optim(c(-1.2, 1), rosenbrock, method = "BFGS")$par
#> [1] 0.9998044 0.9996084
exponential_mass(2, 0, Inf)
#> [1] 1
exponential_mass(2, 0, 1) - pexp(1, 2)
#> [1] -1.110223e-16
tryCatch(minimize_r(function(x) stop("the objective failed"), c(1, 1)),
  error = conditionMessage)
#> [1] "the objective failed"
```
