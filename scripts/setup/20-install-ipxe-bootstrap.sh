#!/usr/bin/env bash
set -euo pipefail

# Install iPXE bootstraps without replacing different existing binaries unless
# FORCE_IPXE=1. A supplied project-root BIOS image has precedence on both OSes.
# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"
require_project_location

content_owner=${NETBOOT_CONTENT_OWNER:-$(id -un)}
tftp_group=${NETBOOT_TFTP_GROUP:-tftp}

ipxe_share=${NETBOOT_IPXE_SHARE_DIR:-/usr/share/ipxe}
family=$(detect_host_family) || exit 1
case "$family" in
    arch)
        source_ipxe="$ipxe_share/x86_64/ipxe.efi"
        packaged_bios="$ipxe_share/x86_64/undionly.kpxe"
        ;;
    fedora)
        source_ipxe="$ipxe_share/ipxe-x86_64.efi"
        packaged_bios="$ipxe_share/undionly.kpxe"
        ;;
esac

source_bios="$PROJECT_ROOT/undionly.kpxe"
destination_uefi="$PROJECT_ROOT/tftp/ipxe.efi"
destination_bios="$PROJECT_ROOT/tftp/undionly.kpxe"

[[ -s "$source_ipxe" ]] || { echo "Missing packaged UEFI iPXE: $source_ipxe" >&2; exit 1; }
if [[ ! -s "$source_bios" ]]; then
    source_bios=$packaged_bios
fi
[[ -s "$source_bios" ]] || { echo "Missing BIOS iPXE: $source_bios" >&2; exit 1; }

check_destination() {
    local source=$1 destination=$2
    if [[ -L "$destination" || ( -e "$destination" && ! -f "$destination" ) ]]; then
        echo "Refusing non-regular bootstrap destination: $destination" >&2
        return 1
    fi
    if [[ -e "$destination" ]] && ! cmp -s "$source" "$destination"; then
        if [[ ${FORCE_IPXE:-0} != 1 ]]; then
            echo "$destination differs from $source; preserving it. Use FORCE_IPXE=1 to replace." >&2
            return 1
        fi
    fi
}

# Reject a conflict before copying either file.
check_destination "$source_ipxe" "$destination_uefi"
check_destination "$source_bios" "$destination_bios"

if [[ ! -d "$PROJECT_ROOT/tftp" ]]; then
    run_as_root install -o "$content_owner" -g "$tftp_group" -d -m 2775 "$PROJECT_ROOT/tftp"
fi
copy_if_needed() {
    local source=$1 destination=$2
    if [[ -e "$destination" ]] && cmp -s "$source" "$destination"; then
        echo "Unchanged iPXE bootstrap: $destination"
    else
        run_as_root install -o "$content_owner" -g "$tftp_group" -m 0644 "$source" "$destination"
        echo "Installed iPXE bootstrap: $destination"
    fi
}
copy_if_needed "$source_ipxe" "$destination_uefi"
copy_if_needed "$source_bios" "$destination_bios"
