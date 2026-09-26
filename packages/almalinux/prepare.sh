#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/setup/_common.sh"
ROOT=$PROJECT_ROOT
PACKAGE_DIR="$ROOT/packages/almalinux"
ISO="$PACKAGE_DIR/AlmaLinux-10-latest-x86_64-boot.iso"
CHECKSUMS="$PACKAGE_DIR/CHECKSUM"
EXPECTED_SHA256=b3f865468075bcada8f208d830289302c67529789d668041d24e8d6fc697ba6a
STAGE="$ROOT/.almalinux-stage"

cd "$ROOT"

if [[ ! -s "$ISO" ]]; then
    echo "Missing AlmaLinux boot ISO: $ISO" >&2
    exit 1
fi

if [[ ! -s "$CHECKSUMS" ]]; then
    echo "Missing AlmaLinux checksum file: $CHECKSUMS" >&2
    exit 1
fi

checksum_line="$(grep -F "SHA256 (AlmaLinux-10-latest-x86_64-boot.iso) =" "$CHECKSUMS" || true)"
[[ "$checksum_line" == *"$EXPECTED_SHA256" ]] || {
    echo "AlmaLinux checksum file does not contain the expected ISO hash" >&2
    exit 1
}

actual="$(sha256sum "$ISO" | awk '{print $1}')"
[[ "$actual" == "$EXPECTED_SHA256" ]] || {
    echo "AlmaLinux boot ISO checksum mismatch" >&2
    echo "expected: $EXPECTED_SHA256" >&2
    echo "actual:   $actual" >&2
    exit 1
}

rm -rf "$STAGE"
mkdir -p "$STAGE" "$PACKAGE_DIR/images"
trap 'rm -rf "$STAGE"' EXIT

for member in images/pxeboot/vmlinuz images/pxeboot/initrd.img images/install.img; do
    bsdtar -tf "$ISO" | grep -Fxq "$member" || {
        echo "Missing confirmed ISO member: $member" >&2
        exit 1
    }
done

bsdtar -xf "$ISO" -C "$STAGE" \
    images/pxeboot/vmlinuz \
    images/pxeboot/initrd.img \
    images/install.img

install -m 0644 "$STAGE/images/pxeboot/vmlinuz" "$PACKAGE_DIR/vmlinuz"
install -m 0644 "$STAGE/images/pxeboot/initrd.img" "$PACKAGE_DIR/initrd.img"
install -m 0644 "$STAGE/images/install.img" "$PACKAGE_DIR/images/install.img"

echo "AlmaLinux installer payload prepared in $PACKAGE_DIR"
