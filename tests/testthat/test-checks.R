key <- function(type) rzig:::.rzig_type_key(type)
input <- function(type) rzig:::.rzig_classify(key(type), rzig:::.rzig_input_types)
output <- function(type) rzig:::.rzig_classify_return(key(type))

test_that("argument types follow the rules of the boundary", {
  for (type in c("f64", "i32", "bool", "usize", "?f64", "[]const f64", "[]const i32",
                 "[]const bool", "[]const u8", "[]const []const u8", "rzig.Matrix",
                 "rzig.Sexp", "rzig.Mut([]f64)")) {
    expect_identical(input(type), "supported", info = type)
  }
  for (type in c("f32", "[]const f32", "i64", "[]f64", "*const f64", "u8", "[]const i64")) {
    expect_identical(input(type), "unsupported", info = type)
  }
  expect_identical(input("Vec"), "local")
  expect_identical(input("[]const Item"), "local")
})

test_that("return types follow the rules of the boundary", {
  for (type in c("void", "f64", "[]f64", "[]const u8", "?[]const u8", "rzig.List",
                 "rzig.Attributed([]f64)", "[][]const u8")) {
    expect_identical(output(type), "supported", info = type)
  }
  for (type in c("f32", "usize", "rzig.Attributed([]const u8)", "rzig.Mut([]f64)")) {
    expect_identical(output(type), "unsupported", info = type)
  }
})

export_record <- function(name, parameters, types, return_type) {
  list(name = name, parameters = parameters, parameter_types = types, return_type = return_type)
}

test_that("signature rules are checked before compilation", {
  check <- function(...) rzig:::.rzig_check_exports(list(export_record(...)))
  many <- paste0("a", 1:33)
  expect_match(check("wide", many, rep("f64", 33L), "f64")$problems, "maximum is 32")
  expect_match(check("two", c("x", "y"), rep("rzig.Mut([]f64)", 2L), "void")$problems, "at most one")
  expect_match(check("ret", "x", "rzig.Mut([]f64)", "[]f64")$problems, "must return void")
  expect_length(check("ok", "x", "rzig.Mut([]f64)", "rzig.Error!void")$problems, 0L)
  expect_match(check("generic", "x", "anytype", "f64")$problems, "anytype")
  expect_match(check("inferred", "x", "f64", "!f64")$problems, "rzig.Error!T")
  expect_match(check("anyerr", "x", "f64", "anyerror!f64")$problems, "rzig.Error!T")
  expect_match(check("single", "x", "f32", "f64")$problems, "use f64")
  local <- check("alias", "x", "Vec", "MyError!f64")
  expect_length(local$problems, 0L)
  expect_length(local$notes, 2L)
})

test_that("the source needs the registration block and the panic handler", {
  path <- local_package("sourcepkg")
  use_rzig(path)
  main <- file.path(path, "src", "rzig", "src", "main.zig")
  expect_length(rzig:::.rzig_check_source(path)$problems, 0L)
  text <- readLines(main)
  writeLines(sub("rzig.registerModule(@This());", "// rzig.registerModule(@This());", text, fixed = TRUE), main)
  expect_match(rzig:::.rzig_check_source(path)$problems, "registerModule")
  writeLines(sub("rzig.Panic;", "std.debug.FullPanic(std.debug.defaultPanic);", text, fixed = TRUE), main)
  expect_match(rzig:::.rzig_check_source(path)$problems, "rzig.Panic")
})

test_that("an R function with the name of an export is reported", {
  path <- local_package("conflictpkg")
  use_rzig(path)
  writeLines("hello_zig <- function(name) name", file.path(path, "R", "mine.R"))
  status <- rzig_status(path)
  expect_false(status$ok[status$step == "Exports"])
  expect_match(status$detail[status$step == "Exports"], "R/mine.R", fixed = TRUE)
})

test_that("framework files from another version and blocked scripts are reported", {
  path <- local_package("scaffoldpkg")
  use_rzig(path)
  expect_length(rzig:::.rzig_check_scaffold(path, "scaffoldpkg")$problems, 0L)
  cat("// edited\n", file = file.path(path, "src", "rzig", "framework", "na.zig"), append = TRUE)
  expect_match(rzig:::.rzig_check_scaffold(path, "scaffoldpkg")$problems, "framework/na.zig", fixed = TRUE)
  use_rzig(path, overwrite = TRUE)
  expect_length(rzig:::.rzig_check_scaffold(path, "scaffoldpkg")$problems, 0L)
  cat("PKG_LIBS += -lm\n", file = file.path(path, "src", "Makevars.in"), append = TRUE)
  expect_match(rzig:::.rzig_check_scaffold(path, "scaffoldpkg")$notes, "Makevars.in", fixed = TRUE)
  skip_on_os("windows")
  Sys.chmod(file.path(path, "configure"), "0644")
  expect_match(rzig:::.rzig_check_scaffold(path, "scaffoldpkg")$problems, "configure not executable")
})

test_that("use_rzig(overwrite = TRUE) keeps the package author's Zig source", {
  path <- local_package("keeppkg")
  use_rzig(path)
  main <- file.path(path, "src", "rzig", "src", "main.zig")
  cat("// written by the package author\n", file = main, append = TRUE)
  extra <- file.path(path, "src", "rzig", "src", "helpers.zig")
  writeLines("pub const two = 2;", extra)
  use_rzig(path, overwrite = TRUE)
  expect_identical(utils::tail(readLines(main), 1L), "// written by the package author")
  expect_true(file.exists(extra))
  ignore <- readLines(file.path(path, ".Rbuildignore"))
  expect_true(all(rzig:::.rzig_buildignore_entries %in% ignore))
  use_rzig(path, overwrite = TRUE)
  expect_identical(sum(readLines(file.path(path, ".Rbuildignore")) == "^src/rzig/zig-out$"), 1L)
})

test_that("the DESCRIPTION check separates failures from notes", {
  path <- local_package("descpkg")
  expect_length(rzig:::.rzig_check_description(path)$problems, 0L)
  expect_match(rzig:::.rzig_check_description(path)$notes, "Title")
  writeLines(c("Package: descpkg", "Version: one"), file.path(path, "DESCRIPTION"))
  expect_match(rzig:::.rzig_check_description(path)$problems, "not a valid package version")
})

test_that("rzig_status fails the Exports row for an unsupported type", {
  path <- local_package("typepkg")
  use_rzig(path)
  main <- file.path(path, "src", "rzig", "src", "main.zig")
  cat("/// @export\npub fn half(x: f32) f32 {\n    return x / 2;\n}\n", file = main, append = TRUE)
  status <- rzig_status(path)
  expect_false(status$ok[status$step == "Exports"])
  expect_match(status$detail[status$step == "Exports"], "type f32 is not supported; use f64", fixed = TRUE)
  expect_output(print(status), "checks failed")
  expect_true("C toolchain" %in% status$step)
})
