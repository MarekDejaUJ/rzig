#!/usr/bin/env Rscript
# GC stress. Turns a one-in-a-million missing PROTECT into a deterministic
# failure by forcing R to collect aggressively.
#
# Usage: Rscript tools/gctorture_run.R [path/to/tests.R]
# Slow (10-100x). Run the full suite nightly, affected tests per PR.

args <- commandArgs(trailingOnly = TRUE)
target <- if (length(args)) args[[1]] else "tests/abuse.R"

if (!file.exists(target)) stop("no such test file: ", target)

library(rzigtest)
message("gctorture ON - this will be slow")
previous_stress <- Sys.getenv("RZIG_GC_STRESS", unset = NA_character_)
Sys.setenv(RZIG_GC_STRESS = "true")
gctorture(TRUE)
res <- tryCatch({ source(target, echo = FALSE); "ok" },
                error = function(e) paste("FAIL:", conditionMessage(e)))
gctorture(FALSE)
if (is.na(previous_stress)) {
  Sys.unsetenv("RZIG_GC_STRESS")
} else {
  Sys.setenv(RZIG_GC_STRESS = previous_stress)
}
message(res)
if (!identical(res, "ok")) quit(status = 1)
