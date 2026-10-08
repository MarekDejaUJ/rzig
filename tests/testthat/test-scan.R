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
  expect_identical(names(table), c("name", "arguments", "return_type", "documented", "line"))
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
