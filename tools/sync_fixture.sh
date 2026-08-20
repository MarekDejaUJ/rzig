#!/bin/sh
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
framework_dir="$repo_dir/tests/fixtures/rzigtest/src/rzig/framework"
mode=${1:---write}
failed=0

framework_files='alloc.zig
attributes.zig
boundary.zig
convert.zig
error_state.zig
interrupt.zig
list.zig
matrix.zig
na.zig
panic.zig
parallel.zig
protect.zig
register.zig
rzig.zig
sexp.zig
unwind.zig
c/abi.zig
generated/arity.zig'

if test "$mode" = "--write"; then
    mkdir -p "$framework_dir/c" "$framework_dir/generated"
elif test "$mode" != "--check"; then
    printf 'usage: %s [--write|--check]\n' "$0" >&2
    exit 2
fi

for relative in $framework_files; do
    source_file="$repo_dir/src/$relative"
    fixture_file="$framework_dir/$relative"
    if test "$mode" = "--write"; then
        cp "$source_file" "$fixture_file"
    elif ! cmp -s "$source_file" "$fixture_file"; then
        printf 'fixture copy is stale: %s\n' "$relative" >&2
        failed=1
    fi
done

repack_source="$repo_dir/tools/repack_macos_archive.sh"
repack_fixture="$repo_dir/tests/fixtures/rzigtest/src/rzig/tools/repack_macos_archive.sh"
if test "$mode" = "--write"; then
    cp "$repack_source" "$repack_fixture"
    chmod +x "$repack_fixture"
elif ! cmp -s "$repack_source" "$repack_fixture"; then
    printf '%s\n' 'fixture copy is stale: tools/repack_macos_archive.sh' >&2
    failed=1
fi

for relative in configure configure.win; do
    source_file="$repo_dir/inst/templates/$relative"
    fixture_file="$repo_dir/tests/fixtures/rzigtest/$relative"
    if test "$mode" = "--write"; then
        cp "$source_file" "$fixture_file"
    elif ! cmp -s "$source_file" "$fixture_file"; then
        printf 'fixture copy is stale: %s\n' "$relative" >&2
        failed=1
    fi
done

abuse_source="$repo_dir/tests/abuse.R"
abuse_fixture="$repo_dir/tests/fixtures/rzigtest/tests/testthat/test-abuse.R"
if test "$mode" = "--write"; then
    cp "$abuse_source" "$abuse_fixture"
elif ! cmp -s "$abuse_source" "$abuse_fixture"; then
    printf 'fixture copy is stale: tests/abuse.R\n' >&2
    failed=1
fi

exit "$failed"
