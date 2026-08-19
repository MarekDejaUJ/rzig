#!/bin/sh
set -eu

if test "${1:-}" = version || test "$#" -eq 0; then
    printf '%s\n' "${FAKE_ZIG_VERSION:-0.16.0}"
    exit 0
fi

printf 'unexpected fake Zig arguments: %s\n' "$*" >&2
exit 2
