#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
repository_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/rzig-scaffold.XXXXXX")
library_dir=$test_root/library
audit_home=$test_root/home
audit_work=$test_root/work
runtime_temp=$test_root/tmp

cleanup() {
    rm -rf "$test_root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$library_dir" "$audit_home" "$audit_work" "$runtime_temp"
R CMD INSTALL --library="$library_dir" "$repository_dir"
(
    cd "$audit_work"
    HOME="$audit_home" \
    R_USER="$audit_home" \
    XDG_CACHE_HOME="$audit_home" \
    TMPDIR="$runtime_temp" \
    ZIG="${ZIG:-zig}" \
    R_LIBS="$library_dir" \
        Rscript --vanilla "$script_dir/check_use_rzig.R"
)

if find "$audit_home" "$audit_work" -mindepth 1 -print -quit | grep -q .; then
    printf '%s\n' 'use_rzig or document wrote outside the explicit package or temp paths' >&2
    exit 1
fi
