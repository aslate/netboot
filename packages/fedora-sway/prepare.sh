#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/setup/_common.sh"
ROOT=$PROJECT_ROOT
PACKAGE_DIR="$ROOT/packages/fedora-sway"
ARCHIVE="$PACKAGE_DIR/Fedora-Sway-Live-44-1.7.x86_64.iso"
CHECKSUMS="$PACKAGE_DIR/Fedora-Spins-44-1.7-x86_64-CHECKSUM"
EXPECTED_SHA256=d18c6e88661ebf86f99cf939b804c7ad51fdcb4f591f6c732e027d2a418b1f05
STAGE="$ROOT/.fedora-sway-stage"

cd "$ROOT"
install -d -m 0755 "$PACKAGE_DIR"

if [[ ! -s "$ARCHIVE" ]]; then
    echo "Missing Fedora Sway archive: $ARCHIVE" >&2
    exit 1
fi

if [[ ! -s "$CHECKSUMS" ]]; then
    echo "Missing Fedora checksum file: $CHECKSUMS" >&2
    exit 1
fi

checksum_line="$(grep -F "SHA256 (Fedora-Sway-Live-44-1.7.x86_64.iso) =" "$CHECKSUMS" || true)"
[[ "$checksum_line" == *"$EXPECTED_SHA256" ]] || {
    echo "Fedora checksum file does not contain the expected ISO hash" >&2
    exit 1
}

actual="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[[ "$actual" == "$EXPECTED_SHA256" ]] || {
    echo "Fedora Sway checksum mismatch" >&2
    echo "expected: $EXPECTED_SHA256" >&2
    echo "actual:   $actual" >&2
    exit 1
}

rm -rf "$STAGE"
mkdir -p "$STAGE"
trap 'rm -rf "$STAGE"' EXIT

for member in \
    boot/x86_64/loader/linux \
    boot/x86_64/loader/initrd \
    LiveOS/squashfs.img; do
    bsdtar -tf "$ARCHIVE" | grep -Fxq "$member" || {
        echo "Missing confirmed ISO member: $member" >&2
        exit 1
    }
done

bsdtar -xf "$ARCHIVE" -C "$STAGE" \
    boot/x86_64/loader/linux \
    boot/x86_64/loader/initrd \
    LiveOS/squashfs.img

[[ -s "$STAGE/boot/x86_64/loader/linux" ]]
[[ -s "$STAGE/boot/x86_64/loader/initrd" ]]
[[ -s "$STAGE/LiveOS/squashfs.img" ]]

install -m 0644 "$STAGE/boot/x86_64/loader/linux" "$PACKAGE_DIR/vmlinuz"
install -m 0644 "$STAGE/boot/x86_64/loader/initrd" "$PACKAGE_DIR/initrd.img"
install -m 0644 "$STAGE/LiveOS/squashfs.img" "$PACKAGE_DIR/squashfs.img"

echo "Fedora Sway payload prepared in $PACKAGE_DIR"
