#!/bin/sh
set -eu

case "$*" in
    RHOME)
        printf '%s\n' "${FAKE_R_HOME:?}"
        ;;
    'CMD config CC')
        printf '%s\n' 'x86_64-test-cc'
        ;;
    *)
        printf 'unexpected fake R arguments: %s\n' "$*" >&2
        exit 2
        ;;
esac
