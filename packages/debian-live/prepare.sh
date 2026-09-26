#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/setup/_common.sh"
ROOT=$PROJECT_ROOT
VERSION=13.7.0
PACKAGE_DIR="$ROOT/packages/debian-live"
ARCHIVE="$PACKAGE_DIR/debian-live-${VERSION}-amd64-standard.iso"
CHECKSUMS="$PACKAGE_DIR/SHA256SUMS"
EXPECTED_SHA256=040a44f35186321eb6cdaab52a8a2d06224fe6b77f6fbb9f1861ad89c14e17ec
STAGE="$ROOT/.debian-live-stage"

cd "$ROOT"
install -d -m 0755 "$PACKAGE_DIR"

if [[ ! -s "$ARCHIVE" ]]; then
    echo "Missing Debian Live archive: $ARCHIVE" >&2
    exit 1
fi

if [[ ! -s "$CHECKSUMS" ]]; then
    echo "Missing Debian checksum file: $CHECKSUMS" >&2
    exit 1
fi

actual="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[[ "$actual" == "$EXPECTED_SHA256" ]] || {
    echo "Debian Live checksum mismatch" >&2
    echo "expected: $EXPECTED_SHA256" >&2
    echo "actual:   $actual" >&2
    exit 1
}

rm -rf "$STAGE"
mkdir -p "$STAGE"
trap 'rm -rf "$STAGE"' EXIT

for name in vmlinuz initrd.img filesystem.squashfs; do
    member="live/$name"
    bsdtar -tf "$ARCHIVE" | grep -Fxq "$member" || {
        echo "Missing confirmed ISO member: $member" >&2
        exit 1
    }
    bsdtar -xf "$ARCHIVE" -C "$STAGE" "$member"
    source="$STAGE/$member"
    [[ -s "$source" ]] || { echo "Empty extracted file: $member" >&2; exit 1; }
    install -m 0644 "$source" "$PACKAGE_DIR/$name"
done

echo "Debian Live payload prepared in $PACKAGE_DIR"
