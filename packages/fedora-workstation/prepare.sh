#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/setup/_common.sh"
ROOT=$PROJECT_ROOT
PACKAGE_DIR="$ROOT/packages/fedora-workstation"
ARCHIVE="$PACKAGE_DIR/Fedora-Workstation-Live-44-1.7.x86_64.iso"
CHECKSUMS="$PACKAGE_DIR/Fedora-Workstation-44-1.7-x86_64-CHECKSUM"
EXPECTED_SHA256=1620295f6a00c27c3208f0c00b8ece4eab1ec69b9002152d97488bf26a426ddf
STAGE="$ROOT/.fedora-workstation-stage"

cd "$ROOT"
install -d -m 0755 "$PACKAGE_DIR"

if [[ ! -s "$ARCHIVE" ]]; then
    echo "Missing Fedora Workstation archive: $ARCHIVE" >&2
    exit 1
fi

if [[ ! -s "$CHECKSUMS" ]]; then
    echo "Missing Fedora checksum file: $CHECKSUMS" >&2
    exit 1
fi

checksum_line="$(grep -F "SHA256 (Fedora-Workstation-Live-44-1.7.x86_64.iso) =" "$CHECKSUMS" || true)"
[[ "$checksum_line" == *"$EXPECTED_SHA256" ]] || {
    echo "Fedora checksum file does not contain the expected ISO hash" >&2
    exit 1
}

actual="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[[ "$actual" == "$EXPECTED_SHA256" ]] || {
    echo "Fedora Workstation checksum mismatch" >&2
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

echo "Fedora Workstation payload prepared in $PACKAGE_DIR"
