#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/setup/_common.sh"
ROOT=$PROJECT_ROOT
MEMDISK="$ROOT/packages/systemrescue/sysresccd/boot/syslinux/memdisk"

if [[ ! -s "$MEMDISK" ]]; then
    echo "Missing shared BIOS memdisk payload: $MEMDISK" >&2
    echo "Prepare the SystemRescue package first." >&2
    exit 1
fi

echo "Super Grub2 Disk package is ready."
echo "UEFI payload: netboot.xyz asset mirror, version 2.06s4"
echo "Legacy BIOS payload: SourceForge hybrid ISO, version 2.04s1"
echo "BIOS memdisk: $MEMDISK"
