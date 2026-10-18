# Compare the R entry points declared in src/c/abi.zig with R's own lists
# (CI step on R release and R-devel). Fails when a declared symbol is in
# tools:::nonAPI, the list R CMD check uses for "Found non-API calls to R";
# reports symbols that tools:::funAPI() lists outside the "api" category.
#
# Usage: Rscript tools/check_api_symbols.R

text <- readLines("src/c/abi.zig", warn = FALSE)
declared <- regmatches(text, regexpr("pub extern (fn|var) [A-Za-z_][A-Za-z0-9_]*", text))
kind <- sub("^pub extern (fn|var) .*$", "\\1", declared)
name <- sub("^pub extern (fn|var) ", "", declared)
non_api <- intersect(c(name, sub("^Rf_", "", name)), tools:::nonAPI)
api <- tools:::funAPI()
listed <- merge(data.frame(name = name, kind = kind), api, by = "name", all.x = TRUE)
other <- listed[listed$kind == "fn" & (is.na(listed$apitype) | listed$apitype != "api"), ]
cat(sprintf("%d R symbols declared (%d functions, %d variables), R %s\n",
  length(name), sum(kind == "fn"), sum(kind == "var"), getRversion()))
if (nrow(other)) {
  cat("functions outside the \"api\" category of tools:::funAPI():\n")
  for (index in seq_len(nrow(other))) {
    cat(sprintf("  %s (%s)\n", other$name[[index]],
      if (is.na(other$apitype[[index]])) "not listed" else other$apitype[[index]]))
  }
}
if (length(non_api)) {
  stop("declared symbols that R CMD check reports as non-API: ", paste(non_api, collapse = ", "),
    call. = FALSE)
}
cat("no declared symbol is in tools:::nonAPI\n")
