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
cleanup=inst/templates/cleanup
cleanup_win=inst/templates/cleanup.win

test -f "$configure_win" || {
    printf '%s\n' 'missing inst/templates/configure.win' >&2
    exit 1
}
test -f "$cleanup" || {
    printf '%s\n' 'missing inst/templates/cleanup' >&2
    exit 1
}
test -f "$cleanup_win" || {
    printf '%s\n' 'missing inst/templates/cleanup.win' >&2
    exit 1
}

require_text "$configure" 'ZIG_SERIES="0.16 0.17"'
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
cp "$cleanup" "$test_dir/cleanup"
cp "$cleanup_win" "$test_dir/cleanup.win"
cp inst/templates/Makevars "$test_dir/src/Makevars.in"
cp inst/templates/Makevars.win "$test_dir/src/Makevars.win.in"
cp tests/configure/fake-zig.sh "$test_dir/fake tools/zig"
cp tests/configure/fake-r.sh "$test_dir/fake-r/bin/R"
chmod +x "$test_dir/configure" "$test_dir/configure.win" \
    "$test_dir/cleanup" "$test_dir/cleanup.win" \
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
(
    cd "$test_dir"
    FAKE_ZIG_VERSION=0.16.0 \
    FAKE_R_HOME="$test_dir/fake-r" \
    FAKE_R_INCLUDE=/usr/share/R/include \
    R_HOME="$test_dir/fake-r" \
    ZIG="$test_dir/fake tools/zig" \
    RZIG_CONFIGURE_PLATFORM=Linux \
        sh ./configure >/dev/null
)
require_text "$test_dir/src/Makevars" "R_INCLUDE_DIR = /usr/share/R/include"
if grep -E -q -- '@[A-Z_]+@' "$test_dir/src/Makevars"; then
    printf '%s\n' 'configure left an unsubstituted Makevars placeholder' >&2
    exit 1
fi

for unsupported in 0.15.2 0.18.0-dev.1234+abcdef 1.0.0 0.17.0-dev.12+abcdef 0.16.0-rc1; do
    if (
        cd "$test_dir"
        FAKE_ZIG_VERSION=$unsupported \
        FAKE_R_HOME="$test_dir/fake-r" \
        R_HOME="$test_dir/fake-r" \
        ZIG="$test_dir/fake tools/zig" \
        RZIG_CONFIGURE_PLATFORM=Linux \
            sh ./configure >/dev/null 2>&1
    ); then
        printf 'configure accepted an unsupported Zig version: %s\n' "$unsupported" >&2
        exit 1
    fi
done

for supported in 0.16.7 0.17.0 0.17.3; do
    (
        cd "$test_dir"
        FAKE_ZIG_VERSION=$supported \
        FAKE_R_HOME="$test_dir/fake-r" \
        R_HOME="$test_dir/fake-r" \
        ZIG="$test_dir/fake tools/zig" \
        RZIG_CONFIGURE_PLATFORM=Linux \
            sh ./configure >/dev/null
    )
done

# Without ZIG, an unsupported zig on PATH must not hide a supported one in the
# usual install locations.
mkdir -p "$test_dir/path bin" "$test_dir/home/.local/share/zig/zig-0.16.1"
printf '#!/bin/sh\nprintf "%%s\\n" 0.15.2\n' > "$test_dir/path bin/zig"
printf '#!/bin/sh\nprintf "%%s\\n" 0.16.1\n' > "$test_dir/home/.local/share/zig/zig-0.16.1/zig"
chmod +x "$test_dir/path bin/zig" "$test_dir/home/.local/share/zig/zig-0.16.1/zig"
(
    cd "$test_dir"
    unset ZIG
    PATH="$test_dir/path bin:$PATH" \
    HOME="$test_dir/home" \
    FAKE_R_HOME="$test_dir/fake-r" \
    R_HOME="$test_dir/fake-r" \
    RZIG_CONFIGURE_PLATFORM=Linux \
        sh ./configure >/dev/null
)
require_text "$test_dir/src/Makevars" "ZIG = $test_dir/home/.local/share/zig/zig-0.16.1/zig"
if (
    cd "$test_dir"
    unset ZIG
    PATH="$test_dir/path bin:$PATH" \
    HOME="$test_dir/empty-home" \
    FAKE_R_HOME="$test_dir/fake-r" \
    R_HOME="$test_dir/fake-r" \
    RZIG_CONFIGURE_PLATFORM=Linux \
        sh ./configure > "$test_dir/reject.out" 2>&1
); then
    printf '%s\n' 'configure accepted Zig 0.15.2 from PATH' >&2
    exit 1
fi
require_text "$test_dir/reject.out" "Zig 0.15.2 found at $test_dir/path bin/zig is an unsupported release series"

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

check_cleanup() {
    script=$1
    mkdir -p "$test_dir/src/rzig/.zig-cache" \
        "$test_dir/src/rzig/.zig-global-cache" "$test_dir/src/rzig/zig-out"
    : > "$test_dir/src/Makevars"
    : > "$test_dir/src/Makevars.win"
    : > "$test_dir/src/rzig/.zig-cache/probe"
    : > "$test_dir/src/rzig/.zig-global-cache/probe"
    : > "$test_dir/src/rzig/zig-out/probe"
    (
        cd "$test_dir"
        sh "./$script"
    )
    test ! -e "$test_dir/src/Makevars"
    test ! -e "$test_dir/src/Makevars.win"
    test ! -e "$test_dir/src/rzig/.zig-cache"
    test ! -e "$test_dir/src/rzig/.zig-global-cache"
    test ! -e "$test_dir/src/rzig/zig-out"
}

check_cleanup cleanup
check_cleanup cleanup.win
