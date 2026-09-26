#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/setup/_common.sh"
ROOT=$PROJECT_ROOT
VERSION=260809
PACKAGE_DIR="$ROOT/packages/cachyos"
ARCHIVE="$PACKAGE_DIR/cachyos-desktop-linux-${VERSION}.iso"
CHECKSUM="$ARCHIVE.sha256"
EXPECTED_SHA256=959f6577f45e25ee9fd8c220fd221b08e4ea79412c7315c0f922dd6d86d5e33c
STAGE="$ROOT/.cachyos-stage"

cd "$ROOT"
install -d -m 0755 "$PACKAGE_DIR"

if [[ ! -s "$ARCHIVE" ]]; then
    echo "Missing CachyOS archive: $ARCHIVE" >&2
    exit 1
fi

if [[ ! -s "$CHECKSUM" ]]; then
    echo "Missing CachyOS checksum file: $CHECKSUM" >&2
    exit 1
fi

actual="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[[ "$actual" == "$EXPECTED_SHA256" ]] || {
    echo "CachyOS checksum mismatch" >&2
    echo "expected: $EXPECTED_SHA256" >&2
    echo "actual:   $actual" >&2
    exit 1
}

rm -rf "$STAGE"
mkdir -p "$STAGE"
trap 'chmod -R u+w "$STAGE" 2>/dev/null || true; rm -rf "$STAGE"' EXIT

# The ISO inspection confirmed that Archiso expects this subtree and that
# the HTTP hook searches it using archisobasedir=arch.
for member in \
    arch/boot/x86_64/vmlinuz-linux-cachyos \
    arch/boot/x86_64/initramfs-linux-cachyos.img \
    arch/x86_64/airootfs.sfs \
    arch/x86_64/airootfs.sha512; do
    bsdtar -tf "$ARCHIVE" | grep -Fxq "$member" || {
        echo "Missing confirmed ISO member: $member" >&2
        exit 1
    }
done

bsdtar -xf "$ARCHIVE" -C "$STAGE" arch
[[ -s "$STAGE/arch/boot/x86_64/vmlinuz-linux-cachyos" ]]
[[ -s "$STAGE/arch/boot/x86_64/initramfs-linux-cachyos.img" ]]
[[ -s "$STAGE/arch/x86_64/airootfs.sfs" ]]
[[ -s "$STAGE/arch/x86_64/airootfs.sha512" ]]

chmod -R u+w "$PACKAGE_DIR/arch" 2>/dev/null || true
rm -rf "$PACKAGE_DIR/arch"
cp -a "$STAGE/arch" "$PACKAGE_DIR/arch"
echo "CachyOS Archiso payload prepared in $PACKAGE_DIR/arch"
