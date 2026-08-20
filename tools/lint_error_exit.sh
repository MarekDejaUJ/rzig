#!/bin/sh
# Rf_error, Rf_warning and Rf_errorcall are longjmp, and
# longjmp skips Zig `defer`. Exactly one file may call them.
#
# If you are reading this because the build failed: do not add an exception.
# Return an error value with rzig.raise() and let the boundary signal it.
set -e

# Files permitted to name these symbols:
#   boundary.zig  the single error exit
#   c/abi.zig     declarations
#   panic.zig     last-resort handler
BAD=$(grep -rn --include='*.zig' -E '\bRf_(error|warning|errorcall)\b' src \
      | grep -v '^src/boundary\.zig:' \
      | grep -v '^src/c/abi\.zig:' \
      | grep -v '^src/panic\.zig:' \
      | awk -F':' '{ rest = $0; sub(/^[^:]*:[0-9]+:/, "", rest);
                     gsub(/^[ \t]+/, "", rest);
                     if (rest !~ /^\/\//) print }' || true)

if [ -n "$BAD" ]; then
  echo "lint: Rf_error/Rf_warning outside the boundary:"
  echo "$BAD"
  exit 1
fi

BAD_INTERRUPTS=$(grep -rn --include='*.zig' --exclude='*_test.zig' \
      -E '\bR_CheckUserInterrupt\b' src \
      | grep -v '^src/c/abi\.zig:' \
      | grep -v '^src/interrupt\.zig:' \
      | awk -F':' '{ rest = $0; sub(/^[^:]*:[0-9]+:/, "", rest);
                     gsub(/^[ \t]+/, "", rest);
                     if (rest !~ /^\/\//) print }' || true)

if [ -n "$BAD_INTERRUPTS" ]; then
  echo "lint: R_CheckUserInterrupt outside its guarded trampoline:"
  echo "$BAD_INTERRUPTS"
  exit 1
fi

echo "lint: error-exit and interrupt-boundary rules OK"
