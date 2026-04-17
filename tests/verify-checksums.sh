#!/bin/sh

set -u

checksum_file=${1:-checksums/v1.5.1.sha256}

fail() {
    printf 'verify-checksums: %s\n' "$1" >&2
    exit 1
}

[ -f "$checksum_file" ] || fail "missing checksum file: $checksum_file"

if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "$checksum_file"
    exit $?
fi

if command -v shasum >/dev/null 2>&1; then
    while IFS= read -r line; do
        case "$line" in
            ''|\#*) continue ;;
        esac

        expected=${line%% *}
        file=${line#*  }
        [ -f "$file" ] || fail "missing file listed in checksums: $file"

        actual=$(shasum -a 256 "$file" | awk '{print $1}')
        [ "$actual" = "$expected" ] || fail "checksum mismatch: $file"
        printf '%s: OK\n' "$file"
    done < "$checksum_file"
    exit 0
fi

fail "sha256sum or shasum is required"
