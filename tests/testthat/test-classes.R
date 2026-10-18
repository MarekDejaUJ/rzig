class_source <- function() read_bytes(fixture_path("class.zig"))

test_that("a struct marked @class gives a constructor and internal methods", {
  exports <- rzig:::.rzig_scan_text(class_source(), "main.zig")
  names <- vapply(exports, function(item) item$name, character(1L))
  expect_identical(names, c("plain", "Counter", "Counter_add", "Counter_value", "Counter_summary"))
  constructor <- exports[[2L]]
  expect_identical(constructor$parameters, "step")
  expect_identical(constructor$defaults, c(step = "1L"))
  expect_false(constructor$internal)
  expect_identical(vapply(constructor$class$methods, function(method) method$name, character(1L)),
    c("add", "value", "summary"))
  expect_identical(exports[[3L]]$parameters, c("self", "times"))
  expect_true(exports[[3L]]$internal)
  expect_identical(exports[[5L]]$parameters, "self")
  checks <- rzig:::.rzig_check_exports(exports)
  expect_length(checks$problems, 0L)
})

test_that("classes render adapters, S3 methods and NAMESPACE registrations", {
  exports <- structure(rzig:::.rzig_scan_text(class_source(), "main.zig"), class = "rzig_exports", package = "clspkg")
  bindings <- render_bindings(exports)
  expect_match(bindings$manifest, "const rzig_class = @import(\"../class.zig\");", fixed = TRUE)
  expect_match(bindings$manifest, ".func = rzig_class.Method(bound_root.Counter, \"add\").call,", fixed = TRUE)
  expect_match(bindings$manifest, ".func = rzig_class.Constructor(bound_root.Counter).call,", fixed = TRUE)
  expect_match(bindings$wrappers, "Counter <- function(step = 1L) {", fixed = TRUE)
  expect_match(bindings$wrappers, "`$.Counter` <- function(x, name) {", fixed = TRUE)
  expect_match(bindings$wrappers, "@section Methods:", fixed = TRUE)
  expect_match(bindings$namespace, 'S3method("$", Counter)', fixed = TRUE)
  expect_match(bindings$namespace, "S3method(utils::.DollarNames, Counter)", fixed = TRUE)
  expect_false(grepl('export("Counter_add")', bindings$namespace, fixed = TRUE))
  roxygen <- render_bindings(exports, roxygen = TRUE)
  expect_match(roxygen$wrappers, "#' @exportS3Method utils::.DollarNames", fixed = TRUE)
  expect_match(roxygen$namespace, 'S3method("$",Counter)', fixed = TRUE)
  page <- rzig:::.rzig_render_rd(exports[[2L]])
  expect_match(page, "\\section{Methods}{", fixed = TRUE)
  expect_match(page, "\\item{\\code{x$add(times)}}{Add the step \\code{times} times and return the count.}", fixed = TRUE)
})

test_that("a class needs init, and members of nested structs are not methods", {
  without_init <- c("/// @class", "pub const Empty = struct {", "    value: f64,",
    "    pub fn get(self: *Empty) f64 {", "        return self.value;", "    }", "};")
  expect_error(rzig:::.rzig_scan_text(paste(without_init, collapse = "\n")), "has no `pub fn init`")
  plain_struct <- c("/// Not a class.", "pub const Point = struct {", "    pub fn init() Point {",
    "        return .{};", "    }", "};")
  expect_length(rzig:::.rzig_scan_text(paste(plain_struct, collapse = "\n")), 0L)
})

test_that("a package with a class builds, keeps state and passes R CMD check", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  root <- local_tempdir()
  path <- file.path(root, "clspkg")
  suppressMessages(create_rzig_package(path, tests = FALSE))
  file.copy(fixture_path("class.zig"), file.path(path, "src", "rzig", "src", "main.zig"), overwrite = TRUE)
  suppressMessages(document(path))
  expect_true(all(rzig_status(path)$ok))
  lib <- file.path(root, "lib")
  dir.create(lib)
  result <- suppressWarnings(build_zig(path, lib = lib))
  expect_true(result$ok)
  output <- run_r(sprintf(paste0(
    ".libPaths(c(%s, .libPaths())); library(clspkg); counter <- Counter(2L); ",
    "cat(class(counter), counter$add(3L), counter$add(1L), counter$value(), '\\n'); ",
    "cat(unlist(counter$summary()), '\\n'); print(counter); ",
    "cat(utils:::.DollarNames(counter, 'a'), '\\n'); ",
    "cat(tryCatch(counter$missing(), error = conditionMessage), '\\n'); ",
    "cat(Counter()$add(5L), '\\n')"
  ), deparse(lib)))
  expect_match(output, "Counter rzig_external 6 8 8", fixed = TRUE)
  expect_match(output, "8 2", fixed = TRUE)
  expect_match(output, "<Counter> with the methods:", fixed = TRUE)
  expect_match(output, "  $add(times)", fixed = TRUE)
  expect_match(output, "add value", fixed = TRUE)
  expect_match(output, "a Counter has no method `missing`; its methods are: add, value, summary", fixed = TRUE)
  expect_match(output, "\n5 $")

  check <- file.path(root, "check")
  dir.create(check)
  old <- setwd(check)
  on.exit(setwd(old), add = TRUE)
  r <- file.path(R.home("bin"), "R")
  built <- suppressWarnings(system2(r, c("CMD", "build", shQuote(path)), stdout = TRUE, stderr = TRUE))
  expect_null(attr(built, "status"))
  tarball <- list.files(check, pattern = "^clspkg_.*[.]tar[.]gz$")
  log <- suppressWarnings(system2(r, c("CMD", "check", "--no-manual", tarball), stdout = TRUE, stderr = TRUE,
    env = c(paste0("ZIG=", find_zig()$path), "_R_CHECK_FORCE_SUGGESTS_=false")))
  status <- grep("^Status:", log, value = TRUE)
  expect_false(any(grepl("ERROR|WARNING", status)), info = paste(log, collapse = "\n"))
})

test_that("roxygen2 registers the S3 methods of a class", {
  skip_on_cran()
  skip_if_not_installed("roxygen2")
  path <- local_package("clsroxy")
  suppressMessages(use_rzig(path))
  file.copy(fixture_path("class.zig"), file.path(path, "src", "rzig", "src", "main.zig"), overwrite = TRUE)
  writeLines(c("# Generated by roxygen2: do not edit by hand", ""), file.path(path, "NAMESPACE"))
  suppressMessages(document(path))
  suppressMessages(roxygen2::roxygenise(path, load_code = roxygen2::load_source))
  namespace <- readLines(file.path(path, "NAMESPACE"))
  expect_true(all(c('S3method("$",Counter)', "S3method(print,Counter)", "S3method(utils::.DollarNames,Counter)",
    "export(Counter)") %in% namespace))
  expect_false("export(Counter_add)" %in% namespace)
  status <- rzig_status(path)
  expect_true(status$ok[status$step == "Bindings"])
})
