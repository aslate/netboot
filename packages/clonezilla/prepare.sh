#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/setup/_common.sh"
ROOT=$PROJECT_ROOT
SERVER_IP=$NETBOOT_SERVER_IP
VERSION=3.3.3-15
PACKAGE_DIR="$ROOT/packages/clonezilla"
ARCHIVE="$PACKAGE_DIR/clonezilla-live-${VERSION}-amd64.zip"
ARCHIVE_URL="https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/${VERSION}/clonezilla-live-${VERSION}-amd64.zip/download"
EXPECTED_SHA256=00cee7700433e63017e2ea9eb40519108829710132364a8028a6c039a6046304
STAGE="$ROOT/.clonezilla-stage"
TARGET="$PACKAGE_DIR"

cd "$ROOT"
install -d -m 0755 "$PACKAGE_DIR" "$STAGE" "$TARGET"

if [[ ! -s "$ARCHIVE" ]]; then
    curl --fail --location --retry 3 --output "$ARCHIVE" "$ARCHIVE_URL"
else
    echo "Using existing Clonezilla archive: $ARCHIVE"
fi

actual="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[[ "$actual" == "$EXPECTED_SHA256" ]] || {
    echo "Clonezilla checksum mismatch" >&2
    echo "expected: $EXPECTED_SHA256" >&2
    echo "actual:   $actual" >&2
    exit 1
}

rm -rf "$STAGE/extracted"
mkdir -p "$STAGE/extracted"
unzip -q "$ARCHIVE" -d "$STAGE/extracted"

for name in vmlinuz initrd.img filesystem.squashfs; do
    source="$STAGE/extracted/live/$name"
    [[ -s "$source" ]] || { echo "Missing live/$name in Clonezilla archive" >&2; exit 1; }
    install -m 0644 "$source" "$TARGET/$name"
done

printf '%s  %s\n' "$EXPECTED_SHA256" "$(basename "$ARCHIVE")" > "$PACKAGE_DIR/${ARCHIVE##*/}.sha256"
cat > "$PACKAGE_DIR/README.md" <<EOF
Clonezilla Live $VERSION amd64

Source archive: $(basename "$ARCHIVE")
Source SHA-256: $EXPECTED_SHA256
Package path: $PACKAGE_DIR/
HTTP base: http://$SERVER_IP/clonezilla/
Boot entry: /clonezilla/boot.ipxe
EOF

rm -rf "$STAGE"
echo "Clonezilla payload prepared in $PACKAGE_DIR"
