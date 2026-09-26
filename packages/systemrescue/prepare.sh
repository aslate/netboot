#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/setup/_common.sh"
ROOT=$PROJECT_ROOT
VERSION=13.02
PACKAGE_DIR="$ROOT/packages/systemrescue"
ARCHIVE="$PACKAGE_DIR/systemrescue-${VERSION}-amd64.iso"
SHA256_FILE="$PACKAGE_DIR/systemrescue-${VERSION}-amd64.iso.sha256"
SHA512_FILE="$PACKAGE_DIR/systemrescue-${VERSION}-amd64.iso.sha512"
STAGE="$ROOT/.systemrescue-stage"

cd "$ROOT"
install -d -m 0755 "$PACKAGE_DIR"

if [[ ! -s "$ARCHIVE" ]]; then
    echo "Missing SystemRescue archive: $ARCHIVE" >&2
    exit 1
fi
if [[ ! -s "$SHA256_FILE" ]]; then
    echo "Missing SystemRescue SHA-256 file: $SHA256_FILE" >&2
    exit 1
fi

(cd "$PACKAGE_DIR" && sha256sum --check "$(basename "$SHA256_FILE")")
if [[ -s "$SHA512_FILE" ]]; then
    (cd "$PACKAGE_DIR" && sha512sum --check "$(basename "$SHA512_FILE")")
fi

rm -rf "$STAGE"
mkdir -p "$STAGE"
trap 'rm -rf "$STAGE"' EXIT

for member in \
    sysresccd/boot/x86_64/vmlinuz \
    sysresccd/boot/x86_64/sysresccd.img \
    sysresccd/boot/intel_ucode.img \
    sysresccd/boot/amd_ucode.img \
    sysresccd/VERSION \
    sysresccd/pkglist.x86_64.txt \
    sysresccd/x86_64/airootfs.sfs \
    sysresccd/x86_64/airootfs.sha512; do
    bsdtar -tf "$ARCHIVE" | grep -Fxq "$member" || {
        echo "Missing confirmed ISO member: $member" >&2
        exit 1
    }
done

bsdtar -xf "$ARCHIVE" -C "$STAGE" sysresccd
[[ -s "$STAGE/sysresccd/boot/x86_64/vmlinuz" ]]
[[ -s "$STAGE/sysresccd/boot/x86_64/sysresccd.img" ]]
[[ -s "$STAGE/sysresccd/boot/intel_ucode.img" ]]
[[ -s "$STAGE/sysresccd/boot/amd_ucode.img" ]]
[[ -s "$STAGE/sysresccd/x86_64/airootfs.sfs" ]]
[[ -s "$STAGE/sysresccd/x86_64/airootfs.sha512" ]]

chmod -R u+w "$PACKAGE_DIR/sysresccd" 2>/dev/null || true
rm -rf "$PACKAGE_DIR/sysresccd"
cp -a "$STAGE/sysresccd" "$PACKAGE_DIR/sysresccd"
echo "SystemRescue payload prepared in $PACKAGE_DIR/sysresccd"
