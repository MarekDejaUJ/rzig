#!/bin/sh
set -eu

check_results() {
    result_dir=$1
    found=0
    failed=0

    for result in \
        "$result_dir"/*.bcheck \
        "$result_dir"/*.maacheck \
        "$result_dir"/*.fficheck
    do
        test -f "$result" || continue
        found=$((found + 1))
        findings=$(grep -E \
            '(^WARNING |^[[:space:]]*\[(PB|UP)\]|^ERROR:)' \
            "$result" | grep -v '^ERROR: too many states' || true)
        if test -n "$findings"; then
            printf 'rchk findings in %s:\n%s\n' "$result" "$findings" >&2
            failed=1
        fi
    done

    if test "$found" -lt 3; then
        printf 'rchk produced %s result files; expected bcheck, maacheck, and fficheck\n' \
            "$found" >&2
        return 1
    fi
    return "$failed"
}

self_test() {
    test_dir=$(mktemp -d)
    trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
    printf '%s\n' 'Analyzed 4 functions, traversed 20 states.' >"$test_dir/test.bcheck"
    printf '%s\n' 'No suspicious calls found.' >"$test_dir/test.maacheck"
    printf '%s\n' 'Initialization function: R_init_test' >"$test_dir/test.fficheck"
    check_results "$test_dir"

    printf '%s\n' '  [UP] unprotected variable value' >>"$test_dir/test.bcheck"
    if check_results "$test_dir" >/dev/null 2>&1; then
        printf '%s\n' 'rchk parser accepted a protection finding' >&2
        return 1
    fi
}

if test "${1:-}" = "--self-test"; then
    self_test
    exit 0
fi
if test "$#" -ne 1 || ! test -d "$1"; then
    printf 'usage: %s RESULT_DIRECTORY\n' "$0" >&2
    exit 2
fi

check_results "$1"
