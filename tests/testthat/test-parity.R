oracle_path <- function() {
  candidates <- c(
    testthat::test_path("..", "..", "tools", "scan.zig"),
    file.path(Sys.getenv("RZIG_REPOSITORY", unset = ""), "tools", "scan.zig")
  )
  candidates <- candidates[nzchar(candidates) & file.exists(candidates)]
  if (!length(candidates)) NULL else normalizePath(candidates[[1L]])
}

run_oracle <- function(zig, scanner, source, package) {
  out <- tempfile("rzig-oracle-")
  dir.create(out)
  old_cache <- Sys.getenv("ZIG_GLOBAL_CACHE_DIR", unset = NA)
  Sys.setenv(ZIG_GLOBAL_CACHE_DIR = file.path(out, "global"))
  on.exit(
    if (is.na(old_cache)) Sys.unsetenv("ZIG_GLOBAL_CACHE_DIR") else Sys.setenv(ZIG_GLOBAL_CACHE_DIR = old_cache),
    add = TRUE
  )
  status <- system2(
    zig,
    c(
      "run", "--cache-dir", shQuote(file.path(out, "cache")),
      "-O", "ReleaseSafe", shQuote(scanner), "--",
      shQuote(source), shQuote(file.path(out, "manifest.zig")),
      shQuote(file.path(out, "wrappers.R")), shQuote(file.path(out, "NAMESPACE")), package
    ),
    stdout = TRUE, stderr = TRUE
  )
  if (!is.null(attr(status, "status"))) stop(paste(status, collapse = "\n"))
  system2(zig, c("fmt", shQuote(file.path(out, "manifest.zig"))), stdout = FALSE, stderr = FALSE)
  list(
    manifest = read_bytes(file.path(out, "manifest.zig")),
    wrappers = read_bytes(file.path(out, "wrappers.R")),
    namespace = read_bytes(file.path(out, "NAMESPACE"))
  )
}

test_that("the R scan agrees with the Zig scanner on every available source", {
  compiler <- find_zig(required = FALSE)
  skip_if_not(isTRUE(compiler$supported), "no supported Zig compiler")
  skip_if_not(
    grepl("^0\\.16\\.", compiler$version),
    "the Zig scanner used as the oracle formats strings as Zig 0.16 does"
  )
  scanner <- oracle_path()
  skip_if(is.null(scanner), "the Zig scanner is only available in the repository")
  sources <- list(
    list(path = fixture_path("edge.zig"), package = "edgepkg"),
    list(path = system.file("zig", "src", "main.zig", package = "rzig"), package = "starter")
  )
  repository <- dirname(dirname(scanner))
  fixture <- file.path(repository, "tests", "fixtures", "rzigtest", "src", "rzig", "src", "main.zig")
  if (file.exists(fixture)) sources[[length(sources) + 1L]] <- list(path = fixture, package = "rzigtest")
  example <- file.path(repository, "examples", "rzigcausal", "src", "rzig", "src", "main.zig")
  if (file.exists(example)) sources[[length(sources) + 1L]] <- list(path = example, package = "rzigcausal")
  for (source in sources) {
    expected <- run_oracle(compiler$path, scanner, normalizePath(source$path), source$package)
    exports <- structure(
      rzig:::.rzig_scan_text(read_bytes(source$path), source$path),
      class = "rzig_exports", package = source$package
    )
    rendered <- render_bindings(exports)
    expect_identical(charToRaw(rendered$manifest), charToRaw(expected$manifest), info = source$path)
    expect_identical(charToRaw(rendered$wrappers), charToRaw(expected$wrappers), info = source$path)
    expect_identical(charToRaw(rendered$namespace), charToRaw(expected$namespace), info = source$path)
  }
})
