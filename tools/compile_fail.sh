#!/bin/sh
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
case_dir="$repo_dir/tests/compile_fail"
zig_path=${ZIG:-zig}
# zig build sets ZIG to its own executable. A build cache restored from an
# earlier CI run can carry the path of a removed installation, so the Zig on
# PATH takes over when ZIG names no executable.
if ! command -v "$zig_path" >/dev/null 2>&1; then
    zig_path=zig
fi
failed=0

for source in "$case_dir"/*.zig; do
    expected=${source%.zig}.expected
    output=$(mktemp)
    if "$zig_path" test \
        --dep boundary \
        --dep registration \
        --dep rzig \
        -Mroot="$source" \
        -Mboundary="$repo_dir/src/boundary.zig" \
        -Mregistration="$repo_dir/src/register.zig" \
        -Mrzig="$repo_dir/src/rzig.zig" \
        -lc >"$output" 2>&1; then
        printf 'compile-fail: %s compiled successfully\n' "$(basename "$source")" >&2
        failed=1
    else
        while IFS= read -r line || test -n "$line"; do
            test -z "$line" && continue
            if ! grep -F -- "$line" "$output" >/dev/null; then
                printf 'compile-fail: %s is missing expected text:\n%s\n' \
                    "$(basename "$source")" "$line" >&2
                sed -n '1,120p' "$output" >&2
                failed=1
            fi
        done <"$expected"
    fi
    rm -f "$output"
done

exit "$failed"
