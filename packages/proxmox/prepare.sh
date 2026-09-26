#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/setup/_common.sh"
ROOT=$PROJECT_ROOT
PACKAGE_DIR="$ROOT/packages/proxmox"
VERSION=9.2-1
ARCHIVE="$PACKAGE_DIR/proxmox-ve_${VERSION}.iso"
PXE_ISO="$PACKAGE_DIR/proxmox-ve_${VERSION}-pxe.iso"
CHECKSUMS="$PACKAGE_DIR/SHA256SUMS"
STAGE="$ROOT/.proxmox-stage"

cd "$ROOT"
install -d -m 0755 "$PACKAGE_DIR"

if [[ ! -s "$ARCHIVE" ]]; then
    echo "Missing Proxmox VE ISO: $ARCHIVE" >&2
    echo "Place the upstream ISO here before running prepare.sh." >&2
    exit 1
fi

if [[ ! -s "$CHECKSUMS" ]]; then
    echo "Missing Proxmox checksum file: $CHECKSUMS" >&2
    echo "Retain the upstream SHA256SUMS file beside the ISO." >&2
    exit 1
fi

expected="$(awk -v name="$(basename "$ARCHIVE")" '$NF == name {gsub(/[()]/, "", $1); print $1; exit}' "$CHECKSUMS")"
[[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] || {
    echo "Could not find a SHA-256 entry for $(basename "$ARCHIVE")" >&2
    exit 1
}

actual="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[[ "$actual" == "$expected" ]] || {
    echo "Proxmox VE ISO checksum mismatch" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
}

for command in xorriso zstd gzip; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Missing required preparation tool: $command" >&2
        exit 1
    }
done

rm -rf "$STAGE"
mkdir -p "$STAGE"
trap 'rm -rf "$STAGE"' EXIT

xorriso -osirrox on -indev "$ARCHIVE" \
    -extract /boot/linux26 "$STAGE/vmlinuz" \
    -extract /boot/initrd.img "$STAGE/initrd.img.zst"

[[ -s "$STAGE/vmlinuz" && -s "$STAGE/initrd.img.zst" ]] || {
    echo "Proxmox ISO did not provide the expected PXE boot files" >&2
    exit 1
}

zstd -d -c "$STAGE/initrd.img.zst" | gzip -c > "$PACKAGE_DIR/initrd.img"
install -m 0644 "$STAGE/vmlinuz" "$PACKAGE_DIR/vmlinuz"
[[ -s "$PACKAGE_DIR/initrd.img" && -s "$PACKAGE_DIR/vmlinuz" ]] || {
    echo "Failed to prepare Proxmox PXE kernel/initramfs" >&2
    exit 1
}

rm -f "$PXE_ISO"
xorriso -boot_image any keep -indev "$ARCHIVE" -outdev "$PXE_ISO" -rm_r /boot
[[ -s "$PXE_ISO" ]] || {
    echo "Failed to create PXE-compatible Proxmox ISO" >&2
    exit 1
}

echo "Verified and prepared Proxmox PXE payload in $PACKAGE_DIR"
