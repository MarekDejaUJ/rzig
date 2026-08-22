package_root <- Sys.getenv("RZIG_ONBOARDING_PACKAGE", unset = "")
install_library <- Sys.getenv("RZIG_ONBOARDING_LIBRARY", unset = "")
if (!nzchar(package_root) || !nzchar(install_library)) {
  stop("onboarding test paths were not supplied")
}

dir.create(package_root)
writeLines(
  c(
    "Package: rzreadme",
    "Type: Package",
    "Title: A Small RZig Example",
    "Version: 0.0.1",
    "Authors@R: person('Test', 'Author', email = 'test@example.org', role = c('aut', 'cre'))",
    "Description: Demonstrates a Zig implementation called safely from R.",
    "License: MIT",
    "Encoding: UTF-8"
  ),
  file.path(package_root, "DESCRIPTION")
)
rzig::use_rzig(package_root)

main_path <- file.path(package_root, "src", "rzig", "src", "main.zig")
main <- readLines(main_path, warn = FALSE)
function_start <- grep("^/// Return a friendly greeting\\.$", main)
registration_start <- grep("^comptime \\{$", main)
stopifnot(length(function_start) == 1L, length(registration_start) == 1L)
replacement <- c(
  "/// Add two numeric vectors elementwise.",
  "/// @param a The first numeric vector.",
  "/// @param b The second numeric vector.",
  "/// @return The elementwise sums.",
  "/// @export",
  "pub fn add_vectors(",
  "    ctx: *rzig.Ctx,",
  "    a: []const f64,",
  "    b: []const f64,",
  ") rzig.Error![]f64 {",
  "    if (a.len != b.len) {",
  "        return rzig.raise(\"lengths differ: {d} vs {d}\", .{ a.len, b.len });",
  "    }",
  "    const result = try ctx.alloc(f64, a.len);",
  "    for (a, b, result) |left, right, *value| value.* = left + right;",
  "    return result;",
  "}"
)
main <- c(
  main[seq_len(function_start - 1L)],
  replacement,
  "",
  main[registration_start:length(main)]
)
stopifnot(
  'const rzig = @import("rzig");' %in% main,
  any(grepl("^pub const panic =", main)),
  "    rzig.registerModule(@This());" %in% main
)
writeLines(
  main,
  main_path,
  useBytes = TRUE
)
rzig::document(package_root)

status <- system2(
  file.path(R.home("bin"), "R"),
  c(
    "CMD", "INSTALL",
    shQuote(paste0("--library=", install_library)),
    shQuote(package_root)
  )
)
if (!identical(status, 0L)) {
  stop("README package installation failed with status ", status)
}

.libPaths(c(install_library, .libPaths()))
add_vectors <- getExportedValue("rzreadme", "add_vectors")
stopifnot(identical(add_vectors(c(1, 2, 3), c(10, 20, 30)), c(11, 22, 33)))

failure <- tryCatch(
  {
    add_vectors(c(1, 2), c(1, 2, 3))
    NULL
  },
  error = identity
)
stopifnot(
  inherits(failure, "error"),
  grepl("lengths differ: 2 vs 3", conditionMessage(failure), fixed = TRUE),
  identical(add_vectors(c(4, 5), c(6, 7)), c(10, 12))
)

wrapper <- readLines(
  file.path(package_root, "R", "rzig-wrappers.R"),
  warn = FALSE
)
stopifnot(
  "#' Add two numeric vectors elementwise." %in% wrapper,
  "#' @param a The first numeric vector." %in% wrapper,
  "#' @param b The second numeric vector." %in% wrapper,
  "#' @return The elementwise sums." %in% wrapper
)

message("README onboarding OK")
