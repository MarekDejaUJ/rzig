#!/bin/sh
# POSIX integration check: deliver a real SIGINT while Zig is polling, then
# assert that R catches an interrupt condition and remains usable. R creates a
# marker file inside the tryCatch() just before it enters the interruptible
# loop, and the signal is sent only after the marker appears, so neither a
# slow start of R nor a busy machine can make the signal arrive outside the
# handler.
set -eu

ready=$(mktemp "${TMPDIR:-/tmp}/rzig-interrupt.XXXXXX")
ready_parallel=$(mktemp "${TMPDIR:-/tmp}/rzig-interrupt-parallel.XXXXXX")
ready_callback=$(mktemp "${TMPDIR:-/tmp}/rzig-interrupt-callback.XXXXXX")
rm -f "$ready" "$ready_parallel" "$ready_callback"
RZIG_INTERRUPT_READY=$ready
RZIG_INTERRUPT_READY_PARALLEL=$ready_parallel
RZIG_INTERRUPT_READY_CALLBACK=$ready_callback
export RZIG_INTERRUPT_READY RZIG_INTERRUPT_READY_PARALLEL RZIG_INTERRUPT_READY_CALLBACK

r_process_id=$$
(
    # One SIGINT for the loop on the R thread, one for the parallel loop and
    # one for an R function that Zig calls.
    for marker in "$ready" "$ready_parallel" "$ready_callback"; do
        waited=0
        while test ! -e "$marker" && test "$waited" -lt 1200; do
            sleep 0.05
            waited=$((waited + 1))
        done
        sleep 0.3
        kill -INT "$r_process_id"
        rm -f "$marker"
    done
) &

exec Rscript -e '
library(rzigtest)
caught <- FALSE
condition <- tryCatch(
  {
    file.create(Sys.getenv("RZIG_INTERRUPT_READY"))
    interruptible_count(2147483647L)
  },
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
caught <- FALSE
condition <- tryCatch(
  {
    file.create(Sys.getenv("RZIG_INTERRUPT_READY_PARALLEL"))
    parallel_count(1e15)
  },
  interrupt = function(value) {
    caught <<- TRUE
    value
  }
)
stopifnot(
  caught,
  inherits(condition, "interrupt"),
  identical(parallel_count(10), 10)
)
caught <- FALSE
before <- call_cleanups()
condition <- tryCatch(
  call_with_cleanup(function() {
    file.create(Sys.getenv("RZIG_INTERRUPT_READY_CALLBACK"))
    repeat Sys.sleep(0.05)
  }),
  interrupt = function(value) {
    caught <<- TRUE
    value
  }
)
stopifnot(
  caught,
  inherits(condition, "interrupt"),
  identical(call_cleanups(), before + 1),
  identical(call_numeric(function(x) x + 1, 1), 2)
)
cat("real SIGINT preserved as interrupt and session recovered, also during a parallel loop and an R callback\n")
'
