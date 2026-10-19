# A knitr engine for Zig chunks

Compiles the code of a chunk with
[`zig_function()`](https://marekdejauj.github.io/rzig/reference/zig_function.md)
and defines its exported functions in the environment of the document,
so later R chunks can call them. rzig registers the engine as `zig` when
knitr is loaded; to register it explicitly, call
`knitr::knit_engines$set(zig = rzig::eng_zig)`.

## Usage

``` r
eng_zig(options)
```

## Arguments

- options:

  The chunk options knitr passes to an engine.

## Value

The chunk output for knitr.

## Examples

``` r
# A document can use a chunk such as
#   ```{zig}
#   pub fn twice(x: f64) f64 { return 2 * x; }
#   ```
# after which R chunks call twice(). The engine is registered as "zig":
if (requireNamespace("knitr", quietly = TRUE)) {
  knitr::knit_engines$set(zig = eng_zig)
  is.function(knitr::knit_engines$get("zig"))
}
#> [1] TRUE
```
