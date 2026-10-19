# Exports, internal routines and classes

The marker `/// @export` makes a public Zig function an R function.
Options of the marker and the documentation lines decide the name, the
defaults and the visibility of the R function; `/// @class` makes a
struct an R class. This vignette shows each form in one package. The
scan and the generated files are plain R; the build and the calls run
when a supported Zig compiler is found (this copy ran them).

``` r

path <- file.path(tempdir(), "exportspkg")
create_rzig_package(path, tests = FALSE)
#> Created package exportspkg at /tmp/RtmpGhnj82/exportspkg
#> Write Zig functions in src/rzig/src/main.zig, then run rzig::document(path) and rzig::build_zig(path)
main_zig <- file.path(path, "src", "rzig", "src", "main.zig")
```

## Names, defaults and invisible results

`name=` gives the R function another name than the Zig function,
`@default` gives an argument a default value written in R, and
`invisible` returns the result invisibly:

``` r

cat(
  "",
  "/// Shrink values towards zero.",
  "/// @param x A numeric vector.",
  "/// @param amount The amount to subtract from each absolute value.",
  "/// @default amount 0.5",
  "/// @return The shrunk values, invisibly.",
  "/// @export name=shrink invisible",
  "pub fn shrink_zig(ctx: *rzig.Ctx, x: []const f64, amount: f64) rzig.Error![]f64 {",
  "    const out = try ctx.alloc(f64, x.len);",
  "    for (x, out) |value, *slot| {",
  "        const size = @max(@abs(value) - amount, 0);",
  "        slot.* = if (value < 0) -size else size;",
  "    }",
  "    return out;",
  "}",
  sep = "\n", file = main_zig, append = TRUE
)
```

## Internal routines

A routine that only the package’s own R code calls is marked
`/// @export internal`: it gets an R wrapper, which the package does not
export and which gets no help page. The exported R function checks its
arguments in R and calls it:

``` r

cat(
  "",
  "/// The weighted mean, for weighted_mean().",
  "/// @export internal",
  "pub fn weighted_mean_zig(x: []const f64, w: []const f64) rzig.Error!f64 {",
  "    if (x.len != w.len) return rzig.raise(\"x and w differ in length\", .{});",
  "    var total: f64 = 0;",
  "    var weights: f64 = 0;",
  "    for (x, w) |value, weight| {",
  "        total += value * weight;",
  "        weights += weight;",
  "    }",
  "    return total / weights;",
  "}",
  sep = "\n", file = main_zig, append = TRUE
)
writeLines(c(
  "#' The weighted mean",
  "#'",
  "#' @param x A numeric vector.",
  "#' @param w Non-negative weights of the same length.",
  "#' @return A number.",
  "#' @export",
  "weighted_mean <- function(x, w = rep(1, length(x))) {",
  "  stopifnot(is.numeric(x), is.numeric(w), all(w >= 0))",
  "  weighted_mean_zig(as.double(x), as.double(w))",
  "}"
), file.path(path, "R", "weighted.R"))
```

## Classes

A struct marked `/// @class` becomes an R class. Its `init` function is
the constructor, exported under the struct’s name, and each public
function that takes the struct as its first parameter is a method,
called with `$`. The object owns the Zig value, which R’s garbage
collector releases:

``` r

cat(
  "",
  "/// A running mean.",
  "/// @class",
  "pub const RunningMean = struct {",
  "    total: f64 = 0,",
  "    count: usize = 0,",
  "",
  "    /// Create an empty running mean.",
  "    pub fn init() RunningMean {",
  "        return .{};",
  "    }",
  "",
  "    /// Add values.",
  "    pub fn add(self: *RunningMean, values: []const f64) void {",
  "        for (values) |value| self.total += value;",
  "        self.count += values.len;",
  "    }",
  "",
  "    /// The mean of the values added so far.",
  "    pub fn mean(self: *const RunningMean) f64 {",
  "        return self.total / @as(f64, @floatFromInt(self.count));",
  "    }",
  "};",
  sep = "\n", file = main_zig, append = TRUE
)
```

## What R sees

The scan lists every export with its R arguments, the internal routine
marked as such, and the constructor and methods of the class:

``` r

scan_exports(path)
#> Zig exports of package exportspkg (src/rzig/src/main.zig): 6 functions
#> 
#> hello_zig(name)
#>   name       []const u8             character, length 1, copied
#>   returns    rzig.Error![]const u8  character, length 1
#> 
#> shrink(x, amount)
#>   x          []const f64            double vector, borrowed
#>   amount     f64                    double, length 1
#>   returns    rzig.Error![]f64       double vector
#> 
#> weighted_mean_zig(x, w)  [internal: not exported from the package]
#>   x          []const f64            double vector, borrowed
#>   w          []const f64            double vector, borrowed
#>   returns    rzig.Error!f64         double, length 1
#> 
#> RunningMean()
#>   returns    rzig.Error!rzig.External(RunningMean) external pointer that owns a Zig value
#> 
#> RunningMean_add(self, values)  [internal: not exported from the package]
#>   self       rzig.External(RunningMean) external pointer to a Zig value of this package
#>   values     []const f64            double vector, borrowed
#>   returns    void                   NULL
#> 
#> RunningMean_mean(self)  [internal: not exported from the package]
#>   self       rzig.External(RunningMean) external pointer to a Zig value of this package
#>   returns    f64                    double, length 1
```

[`document()`](https://marekdejauj.github.io/rzig/reference/document.md)
writes the wrappers; the generated R code shows the default, the
invisible result and the internal routine:

``` r

bindings <- document(path)
#> Generated RZig bindings for exportspkg: 6 exported functions
cat(bindings$wrappers)
#> # Generated by rzig::document(). Do not edit.
#> 
#> #' Return a friendly greeting.
#> #' @param name A name to greet.
#> #' @return A character string.
#> #' @examples
#> #' hello_zig("R")
#> #'
#> #' @export
#> hello_zig <- function(name) {
#>   .Call(hello_zig_, name)
#> }
#> 
#> #' Shrink values towards zero.
#> #' @param x A numeric vector.
#> #' @param amount The amount to subtract from each absolute value.
#> #' @return The shrunk values, invisibly.
#> #'
#> #' @export
#> shrink <- function(x, amount = 0.5) {
#>   invisible(.Call(shrink_, x, amount))
#> }
#> 
#> #' The weighted mean, for weighted_mean().
#> #'
#> #' @keywords internal
#> #' @noRd
#> weighted_mean_zig <- function(x, w) {
#>   .Call(weighted_mean_zig_, x, w)
#> }
#> 
#> #' A running mean.
#> #'
#> #' Create an empty running mean.
#> #'
#> #' @return An object of class `RunningMean`: an external pointer to a Zig value.
#> #' @section Methods:
#> #' For an object `x` made by `RunningMean()`:
#> #' * `x$add(values)`: Add values.
#> #' * `x$mean()`: The mean of the values added so far.
#> #' @export
#> RunningMean <- function() {
#>   .Call(RunningMean_)
#> }
#> 
#> #' Add values.
#> #'
#> #' @keywords internal
#> #' @noRd
#> RunningMean_add <- function(self, values) {
#>   invisible(.Call(RunningMean_add_, self, values))
#> }
#> 
#> #' The mean of the values added so far.
#> #'
#> #' @keywords internal
#> #' @noRd
#> RunningMean_mean <- function(self) {
#>   .Call(RunningMean_mean_, self)
#> }
#> 
#> #' @noRd
#> `$.RunningMean` <- function(x, name) {
#>   methods <- list("add" = RunningMean_add, "mean" = RunningMean_mean)
#>   method <- methods[[name]]
#>   if (is.null(method)) {
#>     stop(sprintf("a RunningMean has no method `%s`; its methods are: %s", name,
#>       paste(names(methods), collapse = ", ")), call. = FALSE)
#>   }
#>   function(...) method(x, ...)
#> }
#> 
#> #' @noRd
#> print.RunningMean <- function(x, ...) {
#>   cat("<RunningMean> with the methods:\n  $add(values)\n  $mean()\n")
#>   invisible(x)
#> }
#> 
#> #' @noRd
#> .DollarNames.RunningMean <- function(x, pattern = "") {
#>   grep(pattern, c("add", "mean"), value = TRUE)
#> }
```

The `NAMESPACE` of the package has a block that
[`document()`](https://marekdejauj.github.io/rzig/reference/document.md)
manages; the lines outside it belong to the package author, here the
export of the R function `weighted_mean()`:

``` r

cat("export(weighted_mean)\n", file = file.path(path, "NAMESPACE"), append = TRUE)
cat(readLines(file.path(path, "NAMESPACE")), sep = "\n")
#> # Generated by rzig::document(): begin
#> useDynLib("exportspkg",
#>   hello_zig_ = "hello_zig",
#>   shrink_ = "shrink",
#>   weighted_mean_zig_ = "weighted_mean_zig",
#>   RunningMean_ = "RunningMean",
#>   RunningMean_add_ = "RunningMean_add",
#>   RunningMean_mean_ = "RunningMean_mean"
#> )
#> export("hello_zig")
#> export("shrink")
#> export("RunningMean")
#> S3method("$", RunningMean)
#> S3method(print, RunningMean)
#> S3method(utils::.DollarNames, RunningMean)
#> # Generated by rzig::document(): end
#> export(weighted_mean)
```

## Build and use

``` r

build <- build_zig(path)
library(build$package, character.only = TRUE, lib.loc = build$library)
shrink(c(-2, 0.2, 3))
print(shrink(c(-2, 0.2, 3), amount = 1))
#> [1] -1  0  2
weighted_mean(c(1, 2, 3), c(1, 1, 2))
#> [1] 2.25
exists("weighted_mean_zig", envir = asNamespace("exportspkg"))
#> [1] TRUE
"weighted_mean_zig" %in% getNamespaceExports("exportspkg")
#> [1] FALSE
m <- RunningMean()
m$add(c(1, 2, 3))
m$add(10)
m$mean()
#> [1] 4
m
#> <RunningMean> with the methods:
#>   $add(values)
#>   $mean()
```

## Customized build files

The build files of the scaffold are templates that the package author
may extend, for example `src/Makevars.in` with additional flags.
[`update_rzig()`](https://marekdejauj.github.io/rzig/reference/update_rzig.md)
keeps such a file and lists it, and
[`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
notes it; the vignette on updating rzig shows both. The framework files
under `src/rzig/framework` belong to rzig and are replaced by every
update.
