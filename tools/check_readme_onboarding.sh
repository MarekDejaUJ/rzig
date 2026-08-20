#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
repository_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/rzig-readme.XXXXXX")
library_dir=$test_root/library
package_dir=$test_root/rzreadme
started=$(date +%s)

cleanup() {
    rm -rf "$test_root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$library_dir"
R CMD INSTALL --library="$library_dir" "$repository_dir"
ZIG=${ZIG:-zig} \
    R_LIBS="$library_dir" \
    RZIG_ONBOARDING_PACKAGE="$package_dir" \
    RZIG_ONBOARDING_LIBRARY="$library_dir" \
    Rscript "$script_dir/check_readme_onboarding.R"

finished=$(date +%s)
elapsed=$((finished - started))
if test "$elapsed" -ge 600; then
    printf 'README onboarding exceeded ten minutes: %s seconds\n' "$elapsed" >&2
    exit 1
fi
printf 'README onboarding completed in %s seconds\n' "$elapsed"
