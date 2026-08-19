#!/bin/sh
# Apple ld requires Mach-O members in static archives to be 8-byte aligned.
# Zig's archive writer can produce a valid generic ar archive that is stricter
# Apple tooling rejects, so rebuild it with the platform libtool before linking.
set -eu

archive=$1
case "$archive" in
    /*) ;;
    *) archive=$PWD/$archive ;;
esac

repack_dir=$(mktemp -d "${TMPDIR:-/tmp}/rzig-archive.XXXXXX")
cleanup() {
    rm -rf "$repack_dir"
}
trap cleanup EXIT HUP INT TERM

cd "$repack_dir"
/usr/bin/ar -x "$archive"
set -- ./*.o
if test ! -e "$1"; then
    echo "no object members found in $archive" >&2
    exit 1
fi
chmod 644 "$@"
/usr/bin/libtool -static -o "$repack_dir/repacked.a" "$@"
mv "$repack_dir/repacked.a" "$archive"
