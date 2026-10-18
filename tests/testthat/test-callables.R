zig_root_header <- c(
  "const std = @import(\"std\");",
  "const rzig = @import(\"rzig\");",
  "",
  "pub const panic = rzig.Panic;",
  "",
  "comptime {",
  "    rzig.registerModule(@This());",
  "}",
  ""
)

test_that("C-callable functions pass between packages with a version check", {
  skip_on_cran()
  skip_if_not(isTRUE(find_zig(required = FALSE)$supported), "no supported Zig compiler")
  root <- local_tempdir()
  lib <- file.path(root, "lib")
  dir.create(lib)
  provider <- file.path(root, "provpkg")
  suppressMessages(create_rzig_package(provider, tests = FALSE))
  writeLines(c(zig_root_header,
    "fn scaledSum(x: [*]const f64, n: usize, factor: f64) callconv(.c) f64 {",
    "    var total: f64 = 0;",
    "    for (x[0..n]) |value| total += value;",
    "    return factor * total;",
    "}",
    "",
    "pub const rzig_callables = .{ .scaled_sum = scaledSum };",
    "pub const rzig_interface_version: u32 = 2;",
    "",
    "/// The interface version of the C-callable functions.",
    "/// @export",
    "pub fn provider_version() i32 {",
    "    return 2;",
    "}"
  ), file.path(provider, "src", "rzig", "src", "main.zig"))
  suppressMessages(document(provider))
  built <- suppressWarnings(build_zig(provider, lib = lib))
  expect_true(built$ok, info = paste(built$log, collapse = "\n"))

  consumer <- file.path(root, "conspkg")
  suppressMessages(create_rzig_package(consumer, tests = FALSE))
  writeLines(c(zig_root_header,
    "const ScaledSum = fn ([*]const f64, usize, f64) callconv(.c) f64;",
    "",
    "/// The scaled sum of provpkg.",
    "/// @export",
    "pub fn use_scaled_sum(ctx: *rzig.Ctx, x: []const f64, factor: f64) rzig.Error!f64 {",
    "    const scaled_sum = try rzig.callable(ctx, ScaledSum, \"provpkg\", \"scaled_sum\", .{ .interface = 2 });",
    "    return scaled_sum(x.ptr, x.len, factor);",
    "}",
    "",
    "/// Ask for an interface version that provpkg does not provide.",
    "/// @export",
    "pub fn wrong_interface(ctx: *rzig.Ctx) rzig.Error!f64 {",
    "    _ = try rzig.callable(ctx, ScaledSum, \"provpkg\", \"scaled_sum\", .{ .interface = 3 });",
    "    return 0;",
    "}",
    "",
    "/// Ask for a function that provpkg does not register.",
    "/// @export",
    "pub fn missing_callable(ctx: *rzig.Ctx) rzig.Error!f64 {",
    "    _ = try rzig.callable(ctx, ScaledSum, \"provpkg\", \"no_such_function\", .{});",
    "    return 0;",
    "}"
  ), file.path(consumer, "src", "rzig", "src", "main.zig"))
  suppressMessages(document(consumer))
  built <- suppressWarnings(build_zig(consumer, lib = lib))
  expect_true(built$ok, info = paste(built$log, collapse = "\n"))
  output <- run_r(paste(
    sprintf(".libPaths(c(%s, .libPaths()))", deparse(lib)),
    "cat('sum', conspkg::use_scaled_sum(c(1, 2, 3), 2), '\\n')",
    "cat('loaded', 'provpkg' %in% loadedNamespaces(), '\\n')",
    "cat('wrong', tryCatch(conspkg::wrong_interface(), error = conditionMessage), '\\n')",
    "cat('missing', tryCatch(conspkg::missing_callable(), error = conditionMessage), '\\n')",
    "cat('again', conspkg::use_scaled_sum(c(4, 5), 1), '\\n')",
    sep = "\n"
  ))
  expect_match(output, "sum 12", fixed = TRUE)
  expect_match(output, "loaded TRUE", fixed = TRUE)
  expect_match(output, "provides version 2 of its C-callable functions, and this package needs version 3", fixed = TRUE)
  expect_match(output, "missing .*no_such_function.*provpkg")
  expect_match(output, "again 9", fixed = TRUE)
})
