#!/bin/sh
# Install a Zig release into /opt and link it as /usr/local/bin/zig.
# Usage: tools/ci_install_zig.sh [version] [arch]
# Tries ziglang.org first and then the community mirrors, so a transient
# failure of one host does not fail the job.
set -eu

version=${1:-0.16.0}
arch=${2:-x86_64-linux}
archive="zig-${arch}-${version}.tar.xz"
target=/opt
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fetch() {
    url=$1
    if curl --fail --silent --show-error --location --retry 3 --retry-delay 5 \
        --output "$tmp/$archive" "$url"; then
        if xz -t "$tmp/$archive" 2>/dev/null; then
            return 0
        fi
        printf 'not an xz archive: %s\n' "$url" >&2
    fi
    return 1
}

if ! fetch "https://ziglang.org/download/${version}/${archive}"; then
    mirrors=$(curl --fail --silent --location https://ziglang.org/download/community-mirrors.txt || true)
    done=0
    for mirror in $mirrors; do
        if fetch "${mirror%/}/${archive}"; then
            done=1
            break
        fi
    done
    if test "$done" -eq 0; then
        printf 'could not download %s from ziglang.org or any mirror\n' "$archive" >&2
        exit 1
    fi
fi

mkdir -p "$target"
tar -xJf "$tmp/$archive" -C "$target"
ln -sf "$target/zig-${arch}-${version}/zig" /usr/local/bin/zig
zig version
