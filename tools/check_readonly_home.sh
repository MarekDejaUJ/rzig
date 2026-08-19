#!/bin/sh
set -eu

archive=${1:-}
if test -z "$archive" || test ! -f "$archive"; then
    printf 'usage: %s path/to/package.tar.gz\n' "$0" >&2
    exit 2
fi

zig_path=${ZIG:-$(command -v zig || true)}
if test -z "$zig_path" || test ! -x "$zig_path"; then
    printf '%s\n' 'set ZIG to an executable Zig compiler' >&2
    exit 2
fi

r_bin=${R_BIN:-$(command -v R || true)}
if test -z "$r_bin" || test ! -x "$r_bin"; then
    printf '%s\n' 'R is required for the read-only HOME check' >&2
    exit 2
fi

test_root=$(mktemp -d "${TMPDIR:-/tmp}/rzig-readonly-home.XXXXXX")
readonly_home=$test_root/home
install_library=$test_root/library
install_tmp=$test_root/tmp

cleanup() {
    chmod u+w "$readonly_home" 2>/dev/null || true
    rm -rf "$test_root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$readonly_home" "$install_library" "$install_tmp"
chmod 0555 "$readonly_home"

HOME="$readonly_home" \
R_USER="$readonly_home" \
XDG_CACHE_HOME="$readonly_home" \
TMPDIR="$install_tmp" \
ZIG="$zig_path" \
    "$r_bin" CMD INSTALL --library="$install_library" "$archive"

if find "$readonly_home" -mindepth 1 -print -quit | grep -q .; then
    printf '%s\n' 'package installation wrote into the read-only HOME' >&2
    exit 1
fi

HOME="$readonly_home" \
R_USER="$readonly_home" \
R_LIBS="$install_library" \
    "$r_bin" --vanilla --slave -e 'library(rzigtest)'

printf '%s\n' 'read-only HOME installation OK'
