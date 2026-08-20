#!/bin/sh
set -eu

script_dir=$(dirname "$0")
test_root=$(mktemp -d "${TMPDIR:-/tmp}/rzig-scaffold.XXXXXX")
library_dir=$test_root/library

cleanup() {
    rm -rf "$test_root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$library_dir"
R CMD INSTALL --library="$library_dir" "$script_dir/.."
ZIG=${ZIG:-zig} R_LIBS="$library_dir" Rscript "$script_dir/check_use_rzig.R"
