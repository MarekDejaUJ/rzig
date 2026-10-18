answer_zon <- c(
  ".{",
  "    .{",
  "        .name = \"answer\",",
  "        .header = \"vendor/answer/answer.h\",",
  "        .sources = .{\"vendor/answer/answer.c\"},",
  "        .include = .{\"vendor/answer\"},",
  "        .flags = .{\"-std=c99\"},",
  "    },",
  "}"
)

write_answer_library <- function(path) {
  vendor <- file.path(path, "src", "rzig", "vendor", "answer")
  dir.create(vendor, recursive = TRUE)
  writeLines(c("int answer(void);", "double scaled(double x, double factor);"), file.path(vendor, "answer.h"))
  writeLines(c(
    "#include \"answer.h\"",
    "int answer(void) { return 42; }",
    "double scaled(double x, double factor) { return x * factor; }"
  ), file.path(vendor, "answer.c"))
  writeLines(answer_zon, file.path(path, "src", "rzig", "c_libraries.zon"))
}

test_that("use_rzig() writes c_libraries.zon and update_rzig() keeps the author's", {
  path <- local_package("clibfiles")
  suppressMessages(use_rzig(path))
  zon <- file.path(path, "src", "rzig", "c_libraries.zon")
  expect_true(file.exists(zon))
  expect_match(paste(readLines(zon), collapse = "\n"), "never replaces this file", fixed = TRUE)
  write_answer_library(path)
  suppressMessages(update_rzig(path))
  expect_identical(readLines(zon), answer_zon)
  scaffold <- rzig:::.rzig_check_scaffold(path, "clibfiles")
  expect_false(any(grepl("c_libraries.zon", c(scaffold$problems, scaffold$notes), fixed = TRUE)))
  unlink(file.path(path, "src", "rzig", "vendor", "answer", "answer.c"))
  expect_true(any(grepl("names files that do not exist: src/rzig/vendor/answer/answer.c",
    rzig:::.rzig_check_scaffold(path, "clibfiles")$problems, fixed = TRUE)))
  unlink(zon)
  expect_true(any(grepl("missing: src/rzig/c_libraries.zon", rzig:::.rzig_check_scaffold(path, "clibfiles")$problems, fixed = TRUE)))
  suppressMessages(update_rzig(path))
  expect_true(file.exists(zon))
})

test_that("a vendored C library is compiled by Zig and called from Zig", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  root <- local_tempdir()
  path <- file.path(root, "clibpkg")
  suppressMessages(create_rzig_package(path, tests = FALSE))
  write_answer_library(path)
  writeLines(c(
    "const rzig = @import(\"rzig\");",
    "const answer = @import(\"answer\");",
    "",
    "pub const panic = rzig.Panic;",
    "",
    "comptime {",
    "    rzig.registerModule(@This());",
    "}",
    "",
    "/// The answer of the vendored C library.",
    "/// @export",
    "pub fn vendored_answer() i32 {",
    "    return answer.answer();",
    "}",
    "",
    "/// Scale each value with the vendored C function.",
    "/// @export",
    "pub fn vendored_scale(ctx: *rzig.Ctx, x: []const f64, factor: f64) rzig.Error![]f64 {",
    "    const out = try ctx.alloc(f64, x.len);",
    "    for (x, out) |value, *slot| slot.* = answer.scaled(value, factor);",
    "    return out;",
    "}"
  ), file.path(path, "src", "rzig", "src", "main.zig"))
  suppressMessages(document(path))
  lib <- file.path(root, "lib")
  dir.create(lib)
  result <- suppressWarnings(build_zig(path, lib = lib))
  expect_true(result$ok, info = paste(result$log, collapse = "\n"))
  output <- run_r(paste(
    sprintf(".libPaths(c(%s, .libPaths()))", deparse(lib)),
    "library(clibpkg)",
    "cat('answer', vendored_answer(), '\\n')",
    "cat('scale', vendored_scale(c(1, 2), 1.5), '\\n')",
    sep = "\n"
  ))
  expect_match(output, "answer 42", fixed = TRUE)
  expect_match(output, "scale 1.5 3", fixed = TRUE)
})
