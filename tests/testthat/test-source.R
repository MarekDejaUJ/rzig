test_that("a snippet gets the header, the markers and the registration it lacks", {
  source <- rzig:::.rzig_snippet_source("pub fn twice(x: f64) f64 { return 2 * x; }")
  expect_identical(source$exports, "twice")
  expect_true('const rzig = @import("rzig");' %in% source$text)
  expect_true("/// @export" %in% source$text)
  expect_true("    rzig.registerModule(@This());" %in% source$text)
  expect_identical(source$inserted, 1L)
  marked <- rzig:::.rzig_snippet_source(c(
    'const std = @import("std");', "/// @export", "pub fn one() f64 {", "    return 1;", "}",
    "pub fn helper() f64 {", "    return 2;", "}"
  ))
  expect_identical(marked$exports, "one")
  expect_identical(sum(marked$text == 'const std = @import("std");'), 1L)
  expect_identical(marked$inserted, 0L)
  expect_identical(marked$text[[marked$offset + 3L]], "pub fn one() f64 {")
  expect_error(rzig:::.rzig_snippet_source("const x = 1;"), "no public function")
})

test_that("zig_function compiles once and defines the functions", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  env <- new.env()
  twice <- zig_function("pub fn twice(x: f64) f64 { return 2 * x; }", env = env)
  expect_identical(twice(21), 42)
  expect_identical(env$twice(1.5), 3)
  start <- Sys.time()
  again <- zig_function("pub fn twice(x: f64) f64 { return 2 * x; }", env = env)
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 2)
  expect_identical(again(2), 4)
  both <- zig_function(c(
    "/// @export", "pub fn add(ctx: *rzig.Ctx, a: []const f64, b: []const f64) rzig.Error![]f64 {",
    "    const out = try ctx.alloc(f64, a.len);",
    "    for (a, b, out) |x, y, *o| o.* = x + y;", "    return out;", "}",
    "/// @export", "pub fn neg(x: f64) f64 {", "    return -x;", "}"
  ), env = env)
  expect_named(both, c("add", "neg"))
  expect_identical(env$add(c(1, 2), c(3, 4)), c(4, 6))
  expect_identical(zig_eval("@sqrt(16.0)", type = "f64"), 4)
  expect_identical(zig_eval("@as(i32, 6) * 7", type = "i32"), 42L)
  file <- tempfile(fileext = ".zig")
  writeLines(c("/// Cube a value.", "/// @export", "pub fn cube(x: f64) f64 {", "    return x * x * x;", "}"), file)
  cube <- zig_source(file, env = env)
  expect_identical(cube(3), 27)
})

test_that("a snippet that does not compile is reported with its own line", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  code <- c("/// @export", "pub fn broken(x: f64) f64 {", "    return x + undefined_name;", "}")
  expect_error(suppressMessages(capture.output(zig_function(code, env = new.env()))),
    "line 3 of the code", fixed = TRUE)
})

test_that("the knitr engine defines Zig functions for later chunks", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  skip_if_not_installed("knitr")
  document <- tempfile(fileext = ".Rmd")
  writeLines(c(
    "```{zig}", "pub fn halve(x: f64) f64 {", "    return x / 2;", "}", "```", "",
    "```{r}", "halve(9)", "```"
  ), document)
  output <- tempfile(fileext = ".md")
  knitr::knit(document, output, quiet = TRUE, envir = new.env())
  text <- readLines(output)
  expect_true(any(grepl("Defined from Zig: halve()", text, fixed = TRUE)))
  expect_true(any(grepl("[1] 4.5", text, fixed = TRUE)))
})
