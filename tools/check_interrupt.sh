#!/bin/sh
# POSIX integration check: deliver a real SIGINT while Zig is polling, then
# assert that R catches an interrupt condition and remains usable.
set -eu

r_process_id=$$
(
    sleep 0.3
    kill -INT "$r_process_id"
) &

exec Rscript -e '
library(rzigtest)
caught <- FALSE
condition <- tryCatch(
  interruptible_count(2147483647L),
  interrupt = function(value) {
    caught <<- TRUE
    value
  }
)
stopifnot(
  caught,
  inherits(condition, "interrupt"),
  !inherits(condition, "error"),
  identical(interruptible_count(1L), 1L)
)
cat("real SIGINT preserved as interrupt and session recovered\n")
'
