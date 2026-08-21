#!/bin/sh
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
asset_dir=$repo_dir/inst/zig/framework
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
rmath.zig
rng.zig
rzig.zig
sexp.zig
unwind.zig
c/abi.zig
generated/arity.zig'

if test "$mode" = "--write"; then
    mkdir -p "$asset_dir/c" "$asset_dir/generated" "$repo_dir/inst/zig/tools"
elif test "$mode" != "--check"; then
    printf 'usage: %s [--write|--check]\n' "$0" >&2
    exit 2
fi

for relative in $framework_files; do
    source_file=$repo_dir/src/$relative
    asset_file=$asset_dir/$relative
    if test "$mode" = "--write"; then
        cp "$source_file" "$asset_file"
    elif ! cmp -s "$source_file" "$asset_file"; then
        printf 'R package asset is stale: %s\n' "$relative" >&2
        failed=1
    fi
done

source_repack=$repo_dir/tools/repack_macos_archive.sh
asset_repack=$repo_dir/inst/zig/tools/repack_macos_archive.sh
if test "$mode" = "--write"; then
    cp "$source_repack" "$asset_repack"
    chmod +x "$asset_repack"
elif ! cmp -s "$source_repack" "$asset_repack"; then
    printf '%s\n' 'R package macOS archive helper is stale' >&2
    failed=1
fi

source_scanner=$repo_dir/tools/scan.zig
asset_scanner=$repo_dir/inst/zig/tools/scan.zig
if test "$mode" = "--write"; then
    cp "$source_scanner" "$asset_scanner"
elif ! cmp -s "$source_scanner" "$asset_scanner"; then
    printf '%s\n' 'R package export scanner is stale'
    failed=1
fi

exit "$failed"
