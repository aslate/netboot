#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/setup/_common.sh"
ROOT=$PROJECT_ROOT
PACKAGE_DIR="$ROOT/packages/fedora-installer"
ARCHIVE="$PACKAGE_DIR/Fedora-Everything-netinst-x86_64-44-1.7.iso"
CHECKSUMS="$PACKAGE_DIR/Fedora-Everything-44-1.7-x86_64-CHECKSUM"
EXPECTED_SHA256=bd285201494dd0ba09b54d05ac707de1401668b8512a573edb5922dcf9d7067e
STAGE="$ROOT/.fedora-installer-stage"

cd "$ROOT"
install -d -m 0755 "$PACKAGE_DIR"

if [[ ! -s "$ARCHIVE" ]]; then
    echo "Missing Fedora Everything netinst archive: $ARCHIVE" >&2
    exit 1
fi

if [[ ! -s "$CHECKSUMS" ]]; then
    echo "Missing Fedora checksum file: $CHECKSUMS" >&2
    exit 1
fi

checksum_line="$(grep -F "SHA256 (Fedora-Everything-netinst-x86_64-44-1.7.iso) =" "$CHECKSUMS" || true)"
[[ "$checksum_line" == *"$EXPECTED_SHA256" ]] || {
    echo "Fedora checksum file does not contain the expected ISO hash" >&2
    exit 1
}

actual="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[[ "$actual" == "$EXPECTED_SHA256" ]] || {
    echo "Fedora Everything netinst checksum mismatch" >&2
    echo "expected: $EXPECTED_SHA256" >&2
    echo "actual:   $actual" >&2
    exit 1
}

rm -rf "$STAGE"
mkdir -p "$STAGE"
trap 'rm -rf "$STAGE"' EXIT

for member in images/pxeboot/vmlinuz images/pxeboot/initrd.img; do
    bsdtar -tf "$ARCHIVE" | grep -Fxq "$member" || {
        echo "Missing confirmed ISO member: $member" >&2
        exit 1
    }
done

bsdtar -xf "$ARCHIVE" -C "$STAGE" images/pxeboot/vmlinuz images/pxeboot/initrd.img

[[ -s "$STAGE/images/pxeboot/vmlinuz" ]]
[[ -s "$STAGE/images/pxeboot/initrd.img" ]]

install -m 0644 "$STAGE/images/pxeboot/vmlinuz" "$PACKAGE_DIR/vmlinuz"
install -m 0644 "$STAGE/images/pxeboot/initrd.img" "$PACKAGE_DIR/initrd.img"

echo "Fedora installer payload prepared in $PACKAGE_DIR"
