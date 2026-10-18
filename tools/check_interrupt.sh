#!/bin/sh
# POSIX integration check: deliver a real SIGINT while Zig is polling, then
# assert that R catches an interrupt condition and remains usable. R creates a
# marker file just before it enters the interruptible loop, and the signal is
# sent only after the marker appears, so a slow start of R cannot make the
# signal arrive before the loop.
set -eu

ready=$(mktemp "${TMPDIR:-/tmp}/rzig-interrupt.XXXXXX")
rm -f "$ready"
RZIG_INTERRUPT_READY=$ready
export RZIG_INTERRUPT_READY

r_process_id=$$
(
    waited=0
    while test ! -e "$ready" && test "$waited" -lt 1200; do
        sleep 0.05
        waited=$((waited + 1))
    done
    sleep 0.3
    kill -INT "$r_process_id"
    rm -f "$ready"
) &

exec Rscript -e '
library(rzigtest)
caught <- FALSE
file.create(Sys.getenv("RZIG_INTERRUPT_READY"))
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
