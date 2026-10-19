# Compare the Zig archives pinned in inst/zig/tools/fetch_zig.R with the
# download index of ziglang.org (CI step; needs network access). Fails when a
# pinned SHA-256 or size differs from the published one.
#
# Usage: Rscript tools/check_zig_pins.R

environment <- new.env(parent = baseenv())
sys.source("inst/zig/tools/fetch_zig.R", envir = environment, keep.source = FALSE)
pins <- environment$rzig_fetch_pins
index_file <- tempfile(fileext = ".json")
status <- utils::download.file("https://ziglang.org/download/index.json", index_file, quiet = TRUE,
  mode = "wb", method = "libcurl")
stopifnot(identical(as.integer(status), 0L))
text <- paste(readLines(index_file, warn = FALSE), collapse = "\n")
mismatches <- character()
for (version in names(pins)) {
  for (platform in names(pins[[version]])) {
    spec <- environment$rzig_fetch_spec(version, platform)
    # The index lists, for each archive, its URL followed by "shasum" and "size".
    pattern <- sprintf('"%s"[[:space:]]*:[[:space:]]*\\{[^}]*"shasum"[[:space:]]*:[[:space:]]*"([0-9a-f]{64})"[^}]*"size"[[:space:]]*:[[:space:]]*"?([0-9]+)"?',
      platform)
    start <- regexpr(sprintf('"%s"[[:space:]]*:[[:space:]]*\\{', gsub(".", "\\.", version, fixed = TRUE)), text)
    if (start < 0) {
      mismatches <- c(mismatches, sprintf("%s: version missing from the index", version))
      next
    }
    release <- substring(text, start)
    found <- regmatches(release, regexec(pattern, release))[[1L]]
    if (length(found) != 3L) {
      mismatches <- c(mismatches, sprintf("%s %s: archive missing from the index", version, platform))
    } else if (!identical(found[[2L]], spec$sha256) || !identical(as.numeric(found[[3L]]), spec$size)) {
      mismatches <- c(mismatches, sprintf("%s %s: pinned %s (%s bytes), published %s (%s bytes)",
        version, platform, spec$sha256, spec$size, found[[2L]], found[[3L]]))
    }
  }
}
if (length(mismatches)) stop("pinned Zig archives differ from the index:\n", paste(mismatches, collapse = "\n"),
  call. = FALSE)
cat(sprintf("%d pinned Zig archives match https://ziglang.org/download/index.json\n",
  sum(lengths(pins))))
