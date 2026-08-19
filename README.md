# RZig

An Rcpp-equivalent for Zig: write plain Zig, get safe R bindings.

**Status: experimental.** The API is under active development and is not yet
ready for production use.

## What it will look like

```zig
const rzig = @import("rzig");

/// Add two numeric vectors elementwise.
/// @export
pub fn add_vectors(ctx: *rzig.Ctx, a: []const f64, b: []const f64) rzig.Error![]f64 {
    if (a.len != b.len) return rzig.raise("lengths differ: {d} vs {d}", .{ a.len, b.len });
    const out = try ctx.alloc(f64, a.len);
    for (a, b, out) |x, y, *o| o.* = x + y;
    return out;
}
```

```r
add_vectors(c(1, 2, 3), c(10, 20, 30))
#> [1] 11 22 33
```

No `SEXP`, no `PROTECT`, no `Rinternals.h`, no C++.

## The design in one paragraph

Rcpp works because C++ has RAII, templates and exceptions. Zig has none of those,
but it has `comptime` reflection, which generates at compile time what C++
generates through templates - with better error messages and no hidden control
flow. The hard part is not the code generation; it is that R's error mechanism is
`longjmp`, which silently skips every Zig `defer`. RZig's answer is to confine
all R-side danger to a single file (`src/boundary.zig`) with exactly one error
exit, so that everything a user writes is ordinary Zig that can be unit-tested
with no R process anywhere.

## Repository map

| Path | What |
|---|---|
| `src/` | Zig implementation (skeletons with TODO markers) |
| `tools/` | Generators, lint, GC-stress runner |
| `tests/` | Zig and R package integration tests |
| `inst/templates/` | What `rzig::use_rzig()` will write into user packages |

## Building and testing

```sh
zig build test
zig build --release=safe
zig build lint
R CMD build tests/fixtures/rzigtest
```

## The five decisions worth knowing up front

1. **Zig emits a static archive; R links the shared object.**
2. **R's C API is declared with hand-written `extern` declarations.**
3. **`/// @export` doc comments identify functions exported to R.**
4. **`Ctx` uses an arena over `c_allocator`, never `R_alloc`.**
5. **Release builds use `ReleaseSafe`, not `ReleaseFast`.**

## License

License information will be added before the first public release.
