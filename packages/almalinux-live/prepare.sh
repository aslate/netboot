#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/setup/_common.sh"
ROOT=$PROJECT_ROOT
PACKAGE_DIR="$ROOT/packages/almalinux-live"
ARCHIVE="$PACKAGE_DIR/AlmaLinux-10.2-x86_64-Live-KDE.iso"
CHECKSUMS="$PACKAGE_DIR/CHECKSUM"
EXPECTED_SHA256=ff3f9c16614abeb672415ba45aaceb358b7765e327961a80ddf69e7c7c3bdf2a
STAGE="$ROOT/.almalinux-live-stage"

cd "$ROOT"

if [[ ! -s "$ARCHIVE" ]]; then
    echo "Missing AlmaLinux Live ISO: $ARCHIVE" >&2
    exit 1
fi

if [[ ! -s "$CHECKSUMS" ]]; then
    echo "Missing AlmaLinux Live checksum file: $CHECKSUMS" >&2
    exit 1
fi

checksum_line="$(awk '$2 == "AlmaLinux-10.2-x86_64-Live-KDE.iso" { print $1 }' "$CHECKSUMS")"
[[ "$checksum_line" == "$EXPECTED_SHA256" ]] || {
    echo "AlmaLinux Live checksum file does not contain the expected ISO hash" >&2
    exit 1
}

actual="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[[ "$actual" == "$EXPECTED_SHA256" ]] || {
    echo "AlmaLinux Live ISO checksum mismatch" >&2
    echo "expected: $EXPECTED_SHA256" >&2
    echo "actual:   $actual" >&2
    exit 1
}

rm -rf "$STAGE"
mkdir -p "$STAGE"
trap 'rm -rf "$STAGE"' EXIT

for member in images/pxeboot/vmlinuz images/pxeboot/initrd.img LiveOS/squashfs.img; do
    bsdtar -tf "$ARCHIVE" | grep -Fxq "$member" || {
        echo "Missing confirmed ISO member: $member" >&2
        exit 1
    }
done

bsdtar -xf "$ARCHIVE" -C "$STAGE" \
    images/pxeboot/vmlinuz \
    images/pxeboot/initrd.img \
    LiveOS/squashfs.img

install -m 0644 "$STAGE/images/pxeboot/vmlinuz" "$PACKAGE_DIR/vmlinuz"
install -m 0644 "$STAGE/images/pxeboot/initrd.img" "$PACKAGE_DIR/initrd.img"
install -m 0644 "$STAGE/LiveOS/squashfs.img" "$PACKAGE_DIR/squashfs.img"

echo "AlmaLinux Live payload prepared in $PACKAGE_DIR"
