#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/setup/_common.sh"
ROOT=$PROJECT_ROOT
VERSION=2.6.2
PACKAGE_DIR="$ROOT/packages/rescuezilla"
ARCHIVE="$PACKAGE_DIR/rescuezilla-${VERSION}-64bit.resolute.iso"
CHECKSUMS="$PACKAGE_DIR/SHA256SUM"
STAGE="$ROOT/.rescuezilla-stage"

cd "$ROOT"
install -d -m 0755 "$PACKAGE_DIR"

if [[ ! -s "$ARCHIVE" ]]; then
    echo "Missing Rescuezilla archive: $ARCHIVE" >&2
    exit 1
fi
if [[ ! -s "$CHECKSUMS" ]]; then
    echo "Missing Rescuezilla checksum file: $CHECKSUMS" >&2
    exit 1
fi

expected="$(awk -v name="$(basename "$ARCHIVE")" '$2 == name {print $1; exit}' "$CHECKSUMS")"
[[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] || {
    echo "Could not find a SHA-256 entry for $(basename "$ARCHIVE")" >&2
    exit 1
}
actual="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[[ "$actual" == "$expected" ]] || {
    echo "Rescuezilla checksum mismatch" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
}

rm -rf "$STAGE"
mkdir -p "$STAGE"
trap 'rm -rf "$STAGE"' EXIT

for member in casper/vmlinuz casper/initrd.lz; do
    bsdtar -tf "$ARCHIVE" | grep -Fxq "$member" || {
        echo "Missing confirmed ISO member: $member" >&2
        exit 1
    }
    bsdtar -xf "$ARCHIVE" -C "$STAGE" "$member"
    [[ -s "$STAGE/$member" ]] || { echo "Empty extracted file: $member" >&2; exit 1; }
done

install -m 0644 "$STAGE/casper/vmlinuz" "$PACKAGE_DIR/vmlinuz"
install -m 0644 "$STAGE/casper/initrd.lz" "$PACKAGE_DIR/initrd.lz"
echo "Rescuezilla casper boot files prepared in $PACKAGE_DIR"
