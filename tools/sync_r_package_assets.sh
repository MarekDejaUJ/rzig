#!/bin/sh
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
asset_dir=$repo_dir/inst/zig/framework
mode=${1:---write}
failed=0

# Every framework source under src/, without the tests, the library entry
# point used by the repository's own fixture build, the ABI-check generator
# and the generated manifest (each package has its own).
framework_files=$(cd "$repo_dir/src" && find . -name '*.zig' \
    ! -name '*_test.zig' ! -name 'main.zig' ! -path './c/check.zig' \
    ! -path './generated/manifest.zig' | sed 's|^\./||' | LC_ALL=C sort)

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

exit "$failed"
