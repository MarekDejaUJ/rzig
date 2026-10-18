edge_exports <- function() {
  text <- read_bytes(fixture_path("edge.zig"))
  structure(rzig:::.rzig_scan_text(text, "edge.zig"), class = "rzig_exports", package = "edgepkg")
}

test_that("the scan finds exported top-level functions in file order", {
  exports <- edge_exports()
  expect_identical(
    vapply(exports, function(item) item$name, character(1L)),
    c("add_values", "r-name", "tag_first", "only_tags", "spaced", "multi",
      "nothing", "foo", "foo_", "twice", "summarize")
  )
  expect_false("helper" %in% vapply(exports, function(item) item$name, character(1L)))
  expect_false("private_helper" %in% vapply(exports, function(item) item$name, character(1L)))
})

test_that("the context parameter is omitted and raw identifiers are decoded", {
  exports <- edge_exports()
  add_values <- exports[[1L]]
  expect_identical(add_values$parameters, c("left", "right"))
  expect_identical(add_values$parameter_types, c("f64", "f64"))
  expect_identical(add_values$return_type, "f64")
  raw <- exports[[2L]]
  expect_identical(raw$identifier, "@\"r-name\"")
  expect_identical(raw$parameters, c("x-value", "if"))
  multi <- exports[[6L]]
  expect_identical(multi$parameters, c("data", "labels", "flag"))
  expect_identical(multi$parameter_types, c("rzig.Matrix", "[]const []const u8", "bool"))
  expect_identical(multi$return_type, "rzig.Error!rzig.Attributed([]const f64)")
  expect_identical(exports[[7L]]$parameters, character())
})

test_that("documentation keeps every line except the export marker", {
  exports <- edge_exports()
  expect_identical(
    exports[[1L]]$doc,
    paste(
      "Add \"values\".",
      "Preserves \\ paths and \"quotes\".",
      "@param left The left-hand value.",
      "@param `right` The right-hand value, documented with backticks.",
      "@return The sum.",
      sep = "\n"
    )
  )
  expect_identical(exports[[2L]]$doc, "")
  expect_identical(exports[[3L]]$doc, "Tag-first documentation after a blank doc line.\n")
  expect_identical(exports[[5L]]$doc, "Documented across a plain comment and a blank line.")
})

test_that("as.data.frame summarizes the exports", {
  table <- as.data.frame(edge_exports())
  expect_identical(names(table), c("name", "arguments", "return_type", "documented", "internal", "line"))
  expect_identical(nrow(table), 11L)
  expect_identical(table$arguments[[6L]], "data, labels, flag")
  expect_true(all(diff(table$line) > 0))
})

test_that("printing describes the R values of every parameter", {
  exports <- edge_exports()
  output <- capture.output(print(exports))
  expect_true(any(grepl("11 functions", output, fixed = TRUE)))
  expect_true(any(grepl("double matrix, borrowed", output, fixed = TRUE)))
  expect_true(any(grepl("double vector, writable duplicate", output, fixed = TRUE)))
  expect_true(any(grepl("the writable duplicate", output, fixed = TRUE)))
  expect_true(any(grepl("named list", output, fixed = TRUE)))
})

test_that("a parameter without a name is reported with the function and position", {
  source <- "/// @export\npub fn broken(x: f64, ...) void {}\n"
  expect_error(
    rzig:::.rzig_scan_text(source, "main.zig"),
    "exported function `broken`: parameter 2 must be written as `name: Type`"
  )
})

test_that("an unbalanced signature is reported with the line", {
  source <- "/// @export\npub fn broken(x: f64 {\n}\n"
  expect_error(rzig:::.rzig_scan_text(source, "main.zig"), "main.zig:2:")
})

test_that("Zig string literals decode escapes", {
  expect_identical(rzig:::.rzig_decode_zig_string("\"a\\\"b\\\\c\\n\\t\""), "a\"b\\c\n\t")
  expect_identical(rzig:::.rzig_decode_zig_string("\"\\x41\\u{142}\""), "A\u0142")
  expect_error(rzig:::.rzig_decode_zig_string("\"\\q\""), "unsupported escape")
})

test_that("/// @export internal marks a registered routine that is not exported", {
  source <- paste(
    "/// A public function.", "/// @export", "pub fn shown(x: f64) f64 {", "    return x;", "}",
    "", "/// A helper for the package's R code.", "/// @export internal",
    "pub fn hidden(x: f64) f64 {", "    return x;", "}", "",
    sep = "\n"
  )
  exports <- rzig:::.rzig_scan_text(source)
  expect_identical(vapply(exports, function(item) item$internal, logical(1L)), c(FALSE, TRUE))
  expect_identical(exports[[2L]]$doc, "A helper for the package's R code.")
  expect_error(rzig:::.rzig_scan_text("/// @export hidden\npub fn f() void {}\n"), "unknown option `hidden`")
  expect_error(rzig:::.rzig_scan_text("/// @export\n/// @export internal\npub fn f() void {}\n"), "more than one")
  frame <- as.data.frame(structure(exports, class = "rzig_exports"))
  expect_identical(frame$internal, c(FALSE, TRUE))
})

test_that("subsetting the exports keeps the class and the attributes", {
  exports <- edge_exports()
  first <- exports[1:2]
  expect_s3_class(first, "rzig_exports")
  expect_length(first, 2L)
  expect_identical(attr(first, "package"), attr(exports, "package"))
  expect_output(print(first), "2 functions")
})

test_that("export options rename, hide the value and give defaults", {
  source <- paste(
    "/// Sum two values.", "/// @param x A number.", "/// @default y 2", "/// @default scale c(a = 1)",
    "/// @export name=sum_two invisible",
    "pub fn sum_zig(x: f64, y: f64, scale: []const f64) f64 {", "    return x + y + scale[0];", "}",
    sep = "\n"
  )
  exports <- rzig:::.rzig_scan_text(source)
  item <- exports[[1L]]
  expect_identical(item$name, "sum_two")
  expect_identical(item$identifier, "sum_zig")
  expect_true(item$invisible)
  expect_identical(item$defaults, c(y = "2", scale = "c(a = 1)"))
  expect_false(grepl("@default", item$doc, fixed = TRUE))
  bindings <- render_bindings(structure(exports, class = "rzig_exports", package = "optpkg"))
  expect_match(bindings$wrappers,
    "sum_two <- function(x, y = 2, scale = c(a = 1)) {\n  invisible(.Call(sum_two_, x, y, scale))\n}", fixed = TRUE)
  expect_match(bindings$manifest, ".name = \"sum_two\",\n                .func = bound_root.sum_zig,", fixed = TRUE)
  expect_match(rzig:::.rzig_render_rd(item), "\\usage{\nsum_two(x, y = 2, scale = c(a = 1))\n}", fixed = TRUE)
})

test_that("invalid export options are errors of the scan", {
  scan <- function(...) rzig:::.rzig_scan_text(paste(..., sep = "\n"))
  expect_error(scan("/// @export name=1bad", "pub fn f() void {}"), "not a syntactic R name")
  expect_error(scan("/// @export quiet", "pub fn f() void {}"), "unknown option `quiet`")
  expect_error(scan("/// @default z 1", "/// @export", "pub fn f(x: f64) f64 {", "    return x;", "}"),
    "not an argument of `f`")
  expect_error(scan("/// @default x 1 +", "/// @export", "pub fn f(x: f64) f64 {", "    return x;", "}"),
    "not one R expression")
})

test_that("parameter and return descriptions follow the type keys", {
  describe <- rzig:::.rzig_describe_parameter
  expect_identical(describe("[]const rzig.Logical"), "logical vector with NA, borrowed")
  expect_identical(describe("rzig.Mut(rzig.Matrix)"), "double matrix, writable duplicate")
  expect_identical(describe("[]const ?[]const u8"), "character vector with NA, copied")
  expect_identical(describe("? f64"), "double, length 1, NA or NULL")
  returns <- rzig:::.rzig_describe_return
  expect_identical(returns("rzig.Error![]rzig.Logical"), "logical vector with NA")
  expect_identical(returns("void", "rzig.Mut(rzig.IntMatrix)"), "the writable duplicate, an integer matrix")
  expect_identical(returns("rzig.Error!rzig.Attributed([]f64)"), "double vector with names, dim or class attributes")
})
