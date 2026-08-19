#!/bin/sh
set -eu

require_text() {
    file=$1
    expected=$2
    if ! grep -F -q -- "$expected" "$file"; then
        printf '%s: missing required text: %s\n' "$file" "$expected" >&2
        exit 1
    fi
}

configure=inst/templates/configure
configure_win=inst/templates/configure.win

test -f "$configure_win" || {
    printf '%s\n' 'missing inst/templates/configure.win' >&2
    exit 1
}

require_text "$configure" 'ZIG_MIN=0.16.0'
require_text "$configure" 'command -v zig'
require_text "$configure" '$HOME/.local/share/zig/'
require_text "$configure" 'CMD config CC'
require_text "$configure" 'Makevars.in'
require_text "$configure_win" 'Makevars.win.in'
require_text "$configure_win" 'Makevars.win'

if grep -F -q -- 'sort -V' "$configure"; then
    printf '%s\n' 'configure must not depend on GNU sort -V' >&2
    exit 1
fi

test_dir=$(mktemp -d "${TMPDIR:-/tmp}/rzig-configure.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
mkdir -p "$test_dir/src" "$test_dir/fake-r/bin" "$test_dir/fake tools"
cp "$configure" "$test_dir/configure"
cp "$configure_win" "$test_dir/configure.win"
cp inst/templates/Makevars "$test_dir/src/Makevars.in"
cp inst/templates/Makevars.win "$test_dir/src/Makevars.win.in"
cp tests/configure/fake-zig.sh "$test_dir/fake tools/zig"
cp tests/configure/fake-r.sh "$test_dir/fake-r/bin/R"
chmod +x "$test_dir/configure" "$test_dir/configure.win" \
    "$test_dir/fake tools/zig" "$test_dir/fake-r/bin/R"

(
    cd "$test_dir"
    FAKE_ZIG_VERSION=0.16.0 \
    FAKE_R_HOME="$test_dir/fake-r" \
    R_HOME="$test_dir/fake-r" \
    ZIG="$test_dir/fake tools/zig" \
    RZIG_CONFIGURE_PLATFORM=Linux \
        sh ./configure
)
require_text "$test_dir/src/Makevars" "ZIG = $test_dir/fake tools/zig"
require_text "$test_dir/src/Makevars" 'ZIG_TARGET_ARG = -Dtarget=x86_64-linux-gnu'
require_text "$test_dir/src/Makevars" "R_INCLUDE_DIR = $test_dir/fake-r/include"
if grep -E -q -- '@[A-Z_]+@' "$test_dir/src/Makevars"; then
    printf '%s\n' 'configure left an unsubstituted Makevars placeholder' >&2
    exit 1
fi

if (
    cd "$test_dir"
    FAKE_ZIG_VERSION=0.15.2 \
    FAKE_R_HOME="$test_dir/fake-r" \
    R_HOME="$test_dir/fake-r" \
    ZIG="$test_dir/fake tools/zig" \
    RZIG_CONFIGURE_PLATFORM=Linux \
        sh ./configure >/dev/null 2>&1
); then
    printf '%s\n' 'configure accepted an unsupported Zig version' >&2
    exit 1
fi

(
    cd "$test_dir"
    FAKE_ZIG_VERSION=0.16.0 \
    FAKE_R_HOME="$test_dir/fake-r" \
    R_HOME="$test_dir/fake-r" \
    ZIG="$test_dir/fake tools/zig" \
        sh ./configure.win
)
require_text "$test_dir/src/Makevars.win" 'ZIG_TARGET_ARG = -Dtarget=x86_64-windows-gnu'
require_text "$test_dir/src/Makevars.win" 'STATLIB = $(ZIG_DIR)/zig-out/lib/zigpkg.lib'
