#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/setup/_common.sh"
ROOT=$PROJECT_ROOT
VERSION=1.8.1-6
PACKAGE_DIR="$ROOT/packages/gparted"
ARCHIVE="$PACKAGE_DIR/gparted-live-${VERSION}-amd64.zip"
EXPECTED_SHA256=cf910dff760d2bbd6d51160529952fa9f3fd80126bab6cd1842f2677508ae1ca
STAGE="$ROOT/.gparted-stage"

cd "$ROOT"
install -d -m 0755 "$PACKAGE_DIR"

if [[ ! -s "$ARCHIVE" ]]; then
    echo "Missing verified GParted archive: $ARCHIVE" >&2
    exit 1
fi

actual="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[[ "$actual" == "$EXPECTED_SHA256" ]] || {
    echo "GParted checksum mismatch" >&2
    echo "expected: $EXPECTED_SHA256" >&2
    echo "actual:   $actual" >&2
    exit 1
}

rm -rf "$STAGE"
mkdir -p "$STAGE/extracted"
unzip -q "$ARCHIVE" -d "$STAGE/extracted"

for name in vmlinuz initrd.img filesystem.squashfs; do
    source="$STAGE/extracted/live/$name"
    [[ -s "$source" ]] || { echo "Missing live/$name in GParted archive" >&2; exit 1; }
    install -m 0644 "$source" "$PACKAGE_DIR/$name"
done

rm -rf "$STAGE"
echo "GParted payload prepared in $PACKAGE_DIR"
