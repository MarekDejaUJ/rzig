package_dir <- tempfile("rzhello-")
dir.create(package_dir)
dir.create(file.path(package_dir, "R"))

writeLines(
  c(
    "Package: rzhello",
    "Type: Package",
    "Title: RZig Scaffold Test",
    "Version: 0.0.1",
    "Authors@R: person('Test', 'Author', email = 'test@example.org', role = c('aut', 'cre'))",
    "Description: Verifies that use_rzig creates an installable Zig-backed package.",
    "License: MIT",
    "Encoding: UTF-8"
  ),
  file.path(package_dir, "DESCRIPTION")
)
writeLines(character(), file.path(package_dir, "NAMESPACE"))

rzig::use_rzig(package_dir)

expected <- c(
  "configure",
  "configure.win",
  "src/entry.c",
  "src/Makevars.in",
  "src/Makevars.win.in",
  "src/rzig/build.zig",
  "src/rzig/build.zig.zon",
  "src/rzig/src/main.zig",
  "src/rzig/framework/rzig.zig",
  "src/rzig/framework/generated/manifest.zig",
  "R/rzig-wrappers.R"
)
missing <- expected[!file.exists(file.path(package_dir, expected))]
if (length(missing)) {
  stop("use_rzig did not create: ", paste(missing, collapse = ", "))
}

namespace <- readLines(file.path(package_dir, "NAMESPACE"), warn = FALSE)
stopifnot(
  any(grepl("useDynLib\\(rzhello", namespace)),
  "export(hello_zig)" %in% namespace
)

install_library <- tempfile("rzhello-library-")
dir.create(install_library)
status <- system2(
  file.path(R.home("bin"), "R"),
  c("CMD", "INSTALL", paste0("--library=", install_library), package_dir)
)
if (!identical(status, 0L)) {
  stop("the scaffolded package failed to install with status ", status)
}

.libPaths(c(install_library, .libPaths()))
loadNamespace("rzhello")
result <- getExportedValue("rzhello", "hello_zig")("Zig")
stopifnot(identical(result, "Hello, Zig!"))

message("use_rzig scaffold OK")
