# Threads, random numbers and CRAN's two-core rule

R’s C API may be called only from the thread that entered R, while Zig
code can run pure computation on several threads. RZig provides parallel
loops whose workers receive plain Zig data only, reductions whose result
does not depend on the number of threads, random streams that follow
[`set.seed()`](https://rdrr.io/r/base/Random.html), and a thread count
that respects the limits of R CMD check. The package below uses all of
them; the build and the calls run when a supported Zig compiler is found
(this copy ran them).

``` r

path <- file.path(tempdir(), "parallelpkg")
create_rzig_package(path, tests = FALSE)
#> Created package parallelpkg at /tmp/RtmpNPzl9E/parallelpkg
#> Write Zig functions in src/rzig/src/main.zig, then run rzig::document(path) and rzig::build_zig(path)
main_zig <- file.path(path, "src", "rzig", "src", "main.zig")
```

## A parallel loop

`rzig.parallelFor(ctx, count, &state, worker)` calls `worker(state, i)`
for every index on worker threads. The state is a pointer to plain Zig
data: the compiler rejects R objects, the call context, pointers to
functions and error unions in it, so a worker cannot call R. The output
slice is allocated before the loop, and each index writes its own
element:

``` r

cat(
  "",
  "const Squares = struct {",
  "    input: []const f64,",
  "    output: []f64,",
  "",
  "    fn run(state: *Squares, index: usize) void {",
  "        state.output[index] = state.input[index] * state.input[index];",
  "    }",
  "};",
  "",
  "/// The squares of the values, computed on worker threads.",
  "/// @param x A numeric vector.",
  "/// @return A numeric vector.",
  "/// @export",
  "pub fn squares(ctx: *rzig.Ctx, x: []const f64) rzig.Error![]f64 {",
  "    const output = try ctx.alloc(f64, x.len);",
  "    var state = Squares{ .input = x, .output = output };",
  "    try rzig.parallelFor(ctx, x.len, &state, Squares.run);",
  "    return output;",
  "}",
  sep = "\n", file = main_zig, append = TRUE
)
```

A user interrupt while the loop runs stops the workers after their
current index and reaches R as an interrupt; a failed safety check on a
worker (an index out of bounds, say) becomes an R error, and the session
continues.

## A reproducible reduction

A floating-point sum depends on the order of its terms.
`rzig.parallelReduce` splits the indices into chunks that depend on the
count alone and adds the chunk results in chunk order, so the sum is the
same for one thread and for eight:

``` r

cat(
  "",
  "const Values = struct {",
  "    values: []const f64,",
  "",
  "    fn value(state: *const Values, index: usize) f64 {",
  "        return state.values[index];",
  "    }",
  "",
  "    fn add(left: f64, right: f64) f64 {",
  "        return left + right;",
  "    }",
  "};",
  "",
  "/// The sum of the values, reduced on worker threads.",
  "/// @param x A numeric vector.",
  "/// @return A number.",
  "/// @export",
  "pub fn parallel_sum(ctx: *rzig.Ctx, x: []const f64) rzig.Error!f64 {",
  "    const state = Values{ .values = x };",
  "    return rzig.parallelReduce(ctx, f64, x.len, &state, 0, Values.value, Values.add);",
  "}",
  sep = "\n", file = main_zig, append = TRUE
)
```

## Random numbers

`ctx.rng()` draws from R’s generator on the thread that entered R, so
draws follow [`set.seed()`](https://rdrr.io/r/base/Random.html) exactly
as [`runif()`](https://rdrr.io/r/stats/Uniform.html) does. Workers
cannot use R’s generator; `ctx.rngStreams()` draws a seed from R’s
stream and gives index `i` its own stream, so parallel draws follow
[`set.seed()`](https://rdrr.io/r/base/Random.html) and do not depend on
the number of threads (they are not the numbers of R’s generator):

``` r
cat(
  "",
  "/// Uniform draws from R's generator.",
  "/// @param n The number of draws.",
  "/// @return A numeric vector.",
  "/// @export",
  "pub fn r_uniforms(ctx: *rzig.Ctx, n: usize) rzig.Error![]f64 {",
  "    const generator = try ctx.rng();",
  "    const out = try ctx.alloc(f64, n);",
  "    for (out) |*slot| slot.* = generator.uniform();",
  "    return out;",
  "}",
  "",
  "const Draws = struct {",
  "    streams: rzig.RngStreams,",
  "    output: []f64,",
  "",
  "    fn draw(state: *Draws, index: usize) void {",
  "        var stream = state.streams.stream(index);",
  "        state.output[index] = stream.normal();",
  "    }",
  "};",
  "",
  "/// Normal draws on worker threads, one stream per index.",
  "/// @param n The number of draws.",
  "/// @return A numeric vector.",
  "/// @export",
  "pub fn stream_normals(ctx: *rzig.Ctx, n: usize) rzig.Error![]f64 {",
  "    const output = try ctx.alloc(f64, n);",
  "    var state = Draws{ .streams = try ctx.rngStreams(), .output = output };",
  "    try rzig.parallelFor(ctx, n, &state, Draws.draw);",
  "    return output;",
  "}",
  sep = "\n", file = main_zig, append = TRUE
)
document(path)
Generated RZig bindings for parallelpkg: 5 exported functions
```

## The number of threads

The loops use one thread per core, at most 32 and at most one per index.
`RZIG_NUM_THREADS` lowers the limit, and `OMP_THREAD_LIMIT` is
respected. While R CMD check limits the cores, which CRAN does for every
submission (`_R_CHECK_LIMIT_CORES_` set to anything but `false`), at
most two threads run, so a package’s examples and tests stay within
CRAN’s two-core rule without code of their own.

## Build and run

``` r

build <- build_zig(path)
library(build$package, character.only = TRUE, lib.loc = build$library)
squares(c(1, 2, 3))
#> [1] 1 4 9
set.seed(1)
x <- rnorm(1e5)
Sys.setenv(RZIG_NUM_THREADS = "1")
one <- parallel_sum(x)
Sys.setenv(RZIG_NUM_THREADS = "8")
eight <- parallel_sum(x)
Sys.unsetenv("RZIG_NUM_THREADS")
identical(one, eight)
#> [1] TRUE
all.equal(one, sum(x))
#> [1] TRUE
set.seed(42)
ours <- r_uniforms(3)
set.seed(42)
identical(ours, runif(3))
#> [1] TRUE
set.seed(7)
first <- stream_normals(5)
set.seed(7)
identical(first, stream_normals(5))
#> [1] TRUE
```
