#!/bin/sh
set -eu

require_line() {
    file=$1
    expected=$2
    if ! grep -F -q -- "$expected" "$file"; then
        printf '%s: missing required text: %s\n' "$file" "$expected" >&2
        exit 1
    fi
}

for file in inst/templates/Makevars inst/templates/Makevars.win; do
    require_line "$file" 'ZIG = @ZIG@'
    require_line "$file" 'ZIG_DIR = rzig'
    require_line "$file" 'OBJECTS = entry.o'
    require_line "$file" 'PKG_LIBS = $(STATLIB)'
    require_line "$file" '--release=safe'
    require_line "$file" '--cache-dir "$(CURDIR)/$(ZIG_DIR)/.zig-cache"'
    require_line "$file" '--global-cache-dir "$(CURDIR)/$(ZIG_DIR)/.zig-global-cache"'
    require_line "$file" '$(SHLIB): $(STATLIB)'
    require_line "$file" 'clean:'
done

require_line inst/templates/Makevars 'ZIG_TARGET_ARG = @ZIG_TARGET_ARG@'
require_line inst/templates/Makevars 'STATLIB = @STATLIB@'
require_line inst/templates/Makevars.win 'ZIG_TARGET_ARG = -Dtarget=x86_64-windows-gnu'
require_line inst/templates/Makevars.win 'STATLIB = $(ZIG_DIR)/zig-out/lib/zigpkg.lib'

if grep -F -q 'libzigpkg.a' inst/templates/Makevars.win; then
    printf '%s\n' 'Makevars.win must use Zig 0.16 Windows archive naming' >&2
    exit 1
fi
