# rzigcausal

`rzigcausal` is a compact causal-discovery package built with RZig. It contains
two computational paths written in plain Zig:

- `correlation_matrix()` computes a Pearson correlation matrix on pure Zig
  worker threads.
- `pc_skeleton()` performs the adjacency-search portion of Gaussian PC-stable
  using Fisher-z conditional-independence tests.

The package is a worked stability and interoperability demonstration. It is not
a replacement for `bnlearn` or `pcalg`: it does not orient edges, represent
separation sets, handle latent confounding, or provide discrete tests. Its
implementation is independent and based on the published algorithm, not copied
from another package.

## Install

From the RZig repository root, with Zig 0.16.0 available:

```sh
R CMD INSTALL examples/rzigcausal
```

If Zig is not on `PATH`, set `ZIG` to its absolute path first.

## Example

The following deterministic construction has the linear chain `x - z - y`.
The end variables are correlated marginally and conditionally independent given
the middle variable.

```r
library(rzigcausal)

n <- 4096L
u1 <- rep(c(-1, 1), length.out = n)
u2 <- rep(c(-1, -1, 1, 1), length.out = n)
u3 <- rep(c(-1, -1, -1, -1, 1, 1, 1, 1), length.out = n)

x <- u1
z <- x + 0.7 * u2
y <- z + 0.7 * u3
observations <- cbind(x, z, y)

correlation_matrix(observations)
pc_skeleton(observations, alpha = 0.05, max_depth = 1L)
#>      [,1] [,2] [,3]
#> [1,]    0    1    0
#> [2,]    1    0    1
#> [3,]    0    1    0
```

`pc_skeleton()` returns an undirected zero-one adjacency matrix. It uses a
depth-frozen adjacency snapshot, so edge removal within one depth does not
depend on variable order in the way the original PC adjacency search can.

## What the example exercises

RZig validates the R matrix shape and exposes its column-major data as a
borrowed, read-only slice. The input is standardized in Zig-owned memory before
the correlation kernel starts. Worker state contains only numeric slices and
dimensions, so no worker can access R's API. The PC search remains on the R
thread and checks for user interrupts as it enumerates conditioning sets.

The implementation rejects non-double matrices, non-finite values, constant
columns, invalid significance levels, undersized data, more than 64 variables,
and conditioning depths above five. These become ordinary R conditions. The
generated package uses `ReleaseSafe`, retaining bounds and integer-overflow
checks in installed code.

## Scope and assumptions

The Gaussian Fisher-z test assumes independent observations from a multivariate
normal distribution. Causal interpretation additionally requires the usual PC
assumptions, including causal sufficiency, the causal Markov condition, and
faithfulness. The returned skeleton alone does not identify edge directions.
Use a mature causal-discovery package for scientific analysis.

The implementation follows the Gaussian PC adjacency search described by
[Kalisch and Bühlmann (2007)](https://jmlr.org/papers/v8/kalisch07a.html) and
freezes adjacency sets by depth following
[Colombo and Maathuis (2014)](https://jmlr.org/papers/v15/colombo14a.html).

## Verify

```sh
R CMD build examples/rzigcausal
R CMD check --as-cran --no-manual rzigcausal_0.1.0.tar.gz
```

The tests compare the Zig correlation kernel with base R, recover the known
chain skeleton, check variable-order stability, exercise hostile inputs, verify
that inputs remain unchanged, and confirm that the R session works after every
native error. `tools/gctorture.R` repeatedly exercises successful calls and
native error recovery with R allocation stress enabled.
