# Tests

```
tests/
  fixtures/rzigtest/     a real R package exercising every supported type,
                         and the worked example in the README
  abuse.R                hostile inputs; asserts the SESSION SURVIVES,
                         not that answers are right
  compile_fail/          unsupported signatures + expected error substrings
  bench.R                round-trip timing vs hand-written C and vs Rcpp
```

## The abuse suite is the important one

For every exported function, call it with: wrong SEXPTYPE, length 0, length 2
where 1 is expected, `NA`, `NaN`, `Inf`, `NULL`, a list, an S4 object, a large
ALTREP sequence, astral-plane UTF-8, Latin-1, and a string with an embedded nul.

Pass condition is that every failure arrived as an R condition naming the
offending argument, and R is still running afterwards. A framework that returns
correct answers for correct input is not interesting; every hand-written binding
does that. The value is in what happens when input is wrong.

## Per-type coverage checklist

Six cases per supported type: happy small, happy 1e6, length 0, NA present,
wrong type, ALTREP variant where one exists.

## Native analysis

Linux CI runs the fixture through valgrind on every change. The scheduled
`rchk` workflow checks the package's C registration and ABI bridge. Current
`rchk` uses LLVM 14 bitcode, which cannot consume the newer LLVM bitcode emitted
by Zig 0.16, so Zig-side protection paths are instead exercised by the full
gctorture and valgrind suites. This limitation should be revisited when the two
tools share a compatible LLVM bitcode version.

## Performance

Install the fixture package, then run `Rscript tests/bench.R`. The benchmark
compiles equivalent handwritten C and Rcpp round-trip copies, checks their
results, and times lengths 1, 1,000, and 1,000,000 in randomized batches. Set
`RZIG_BENCH_BATCHES` to change the default 21 batches and
`RZIG_BENCH_OUTPUT` to save the summary as CSV.
