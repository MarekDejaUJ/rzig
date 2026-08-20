#!/usr/bin/env Rscript

if (!requireNamespace("rzigtest", quietly = TRUE)) {
  stop(
    "install tests/fixtures/rzigtest before running this benchmark",
    call. = FALSE
  )
}

parse_positive_integer <- function(name, default) {
  value <- Sys.getenv(name, unset = as.character(default))
  parsed <- suppressWarnings(as.integer(value))
  if (is.na(parsed) || parsed < 1L) {
    stop(name, " must be a positive integer", call. = FALSE)
  }
  parsed
}

compile_c_baseline <- function(directory) {
  source <- file.path(directory, "rzig_bench_c.c")
  writeLines(c(
    "#include <R.h>",
    "#include <Rinternals.h>",
    "",
    "#include <string.h>",
    "",
    "SEXP rzig_roundtrip_c(SEXP x) {",
    "    if (TYPEOF(x) != REALSXP) Rf_error(\"x must be a numeric vector\");",
    "    R_xlen_t n = XLENGTH(x);",
    "    const double *input = REAL_RO(x);",
    "    SEXP result = PROTECT(Rf_allocVector(REALSXP, n));",
    "    double *output = REAL(result);",
    "    if (n > 0) memcpy(output, input, (size_t)n * sizeof(double));",
    "    UNPROTECT(1);",
    "    return result;",
    "}"
  ), source)

  old_directory <- setwd(directory)
  on.exit(setwd(old_directory), add = TRUE)
  output <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "SHLIB", basename(source)),
    stdout = TRUE,
    stderr = TRUE
  )
  status <- attr(output, "status")
  if (!is.null(status) && status != 0L) {
    stop(paste(c("failed to compile the C baseline", output), collapse = "\n"),
      call. = FALSE
    )
  }

  library <- dyn.load(file.path(directory, paste0("rzig_bench_c", .Platform$dynlib.ext)))
  symbol <- getNativeSymbolInfo("rzig_roundtrip_c", PACKAGE = library)
  function(x) .Call(symbol, x)
}

compile_rcpp_baseline <- function(directory) {
  if (!requireNamespace("Rcpp", quietly = TRUE)) return(NULL)

  environment <- new.env(parent = baseenv())
  Rcpp::sourceCpp(
    code = paste(
      "#include <Rcpp.h>",
      "#include <algorithm>",
      "// [[Rcpp::export]]",
      "Rcpp::NumericVector rzig_roundtrip_rcpp(const Rcpp::NumericVector& x) {",
      "    R_xlen_t n = x.size();",
      "    Rcpp::NumericVector result(Rcpp::no_init(n));",
      "    std::copy(x.begin(), x.end(), result.begin());",
      "    return result;",
      "}",
      sep = "\n"
    ),
    env = environment,
    cacheDir = file.path(directory, "rcpp-cache"),
    rebuild = TRUE,
    showOutput = FALSE,
    verbose = FALSE
  )
  environment$rzig_roundtrip_rcpp
}

time_batch <- function(fun, input, iterations) {
  start <- as.numeric(Sys.time())
  for (iteration in seq_len(iterations)) result <- fun(input)
  elapsed <- as.numeric(Sys.time()) - start
  if (length(result) != length(input)) stop("benchmark result has the wrong length")
  elapsed / iterations
}

benchmark_directory <- tempfile("rzig-bench-")
dir.create(benchmark_directory)

rzig_symbol <- get("C_echo_reals", envir = asNamespace("rzigtest"))
rzig_roundtrip <- function(x) .Call(rzig_symbol, x)

implementations <- list(
  RZig = rzig_roundtrip,
  C = compile_c_baseline(benchmark_directory)
)
rcpp <- compile_rcpp_baseline(benchmark_directory)
if (!is.null(rcpp)) implementations$Rcpp <- rcpp

sizes <- c(1L, 1000L, 1000000L)
inner_iterations <- c(`1` = 50000L, `1000` = 5000L, `1000000` = 10L)
batches <- parse_positive_integer("RZIG_BENCH_BATCHES", 21L)
set.seed(20260820L)

cat("RZig boundary benchmark\n")
cat("R:", R.version.string, "\n")
cat("Platform:", R.version$platform, "\n")
cat("OS:", paste(Sys.info()[c("sysname", "release", "machine")], collapse = " "), "\n")
cat("rzigtest:", as.character(utils::packageVersion("rzigtest")), "\n")
cat("Rcpp:", if (is.null(rcpp)) "not installed" else as.character(utils::packageVersion("Rcpp")), "\n")
cat("Batches:", batches, "\n\n")

timings <- list()
row <- 0L
for (size in sizes) {
  input <- as.double(seq_len(size)) / max(1, size)
  expected <- input

  for (name in names(implementations)) {
    observed <- implementations[[name]](input)
    if (!identical(observed, expected)) {
      stop(name, " produced an incorrect result at length ", size, call. = FALSE)
    }
    invisible(implementations[[name]](input))
  }

  iterations <- unname(inner_iterations[as.character(size)])
  for (batch in seq_len(batches)) {
    for (name in sample(names(implementations))) {
      invisible(gc(verbose = FALSE))
      row <- row + 1L
      timings[[row]] <- data.frame(
        size = size,
        implementation = name,
        batch = batch,
        seconds_per_call = time_batch(implementations[[name]], input, iterations),
        stringsAsFactors = FALSE
      )
    }
  }
}
timings <- do.call(rbind, timings)

keys <- unique(timings[c("size", "implementation")])
summary <- do.call(rbind, lapply(seq_len(nrow(keys)), function(index) {
  selected <- timings$size == keys$size[index] &
    timings$implementation == keys$implementation[index]
  values <- timings$seconds_per_call[selected] * 1e9
  data.frame(
    size = keys$size[index],
    implementation = keys$implementation[index],
    median_ns = stats::median(values),
    q25_ns = unname(stats::quantile(values, 0.25)),
    q75_ns = unname(stats::quantile(values, 0.75)),
    batches = length(values),
    stringsAsFactors = FALSE
  )
}))
summary <- summary[order(summary$size, match(summary$implementation, names(implementations))), ]
row.names(summary) <- NULL

baseline_ratio <- function(implementation) {
  baseline <- summary[summary$implementation == implementation, c("size", "median_ns")]
  summary$median_ns / baseline$median_ns[match(summary$size, baseline$size)]
}
summary$ratio_to_c <- baseline_ratio("C")
summary$ratio_to_rcpp <- if (is.null(rcpp)) NA_real_ else baseline_ratio("Rcpp")

display <- summary
display$median_us <- display$median_ns / 1000
display$iqr_us <- (display$q75_ns - display$q25_ns) / 1000
display <- display[c("size", "implementation", "median_us", "iqr_us", "ratio_to_c", "ratio_to_rcpp")]
print(display, row.names = FALSE, digits = 4)

largest <- max(sizes)
if (is.null(rcpp)) {
  cat("\nRcpp comparison not evaluated: install Rcpp to include it.\n")
} else {
  large_ratio <- summary$ratio_to_rcpp[
    summary$size == largest & summary$implementation == "RZig"
  ]
  cat(sprintf(
    "\nOne-million-element RZig/Rcpp ratio: %.3f (%s; target <= 1.100)\n",
    large_ratio,
    if (large_ratio <= 1.1) "PASS" else "GAP"
  ))
}

output_file <- Sys.getenv("RZIG_BENCH_OUTPUT", unset = "")
if (nzchar(output_file)) {
  utils::write.csv(summary, output_file, row.names = FALSE)
  cat("Wrote:", normalizePath(output_file, mustWork = FALSE), "\n")
}
