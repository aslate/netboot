#!/usr/bin/env bash
set -euo pipefail

# Recreate the stable Caddy-facing links into package trees. This is useful
# after copying the project with a tool that did not preserve symlinks.
# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

require_project_location

links=(
    "http/alma10|../alma10"
    "http/almalinux|../packages/almalinux"
    "http/almalinux-live|../packages/almalinux-live"
    "http/cachyos|../packages/cachyos"
    "http/clonezilla|../packages/clonezilla"
    "http/debian-live|../packages/debian-live"
    "http/fedora-installer|../packages/fedora-installer"
    "http/fedora-sway|../packages/fedora-sway"
    "http/fedora-workstation|../packages/fedora-workstation"
    "http/gparted|../packages/gparted"
    "http/kickstarts|../packages/almalinux"
    "http/rescuezilla|../packages/rescuezilla"
    "http/proxmox|../packages/proxmox"
    "http/systemrescue|../packages/systemrescue"
    "http/supergrub|../packages/supergrub"
    "http/menu/almalinux.ipxe|../../packages/almalinux/boot.ipxe"
)

# Check every destination first, so a collision cannot leave a half-repaired
# link set. Wrong symlinks are safe to replace; real objects are not.
for mapping in "${links[@]}"; do
    destination="$PROJECT_ROOT/${mapping%%|*}"
    if [[ -e "$destination" && ! -L "$destination" ]]; then
        echo "Refusing to replace non-symlink: $destination" >&2
        exit 1
    fi
done

mkdir -p "$PROJECT_ROOT/http" "$PROJECT_ROOT/http/menu" \
    "$PROJECT_ROOT/http/ipxe" "$PROJECT_ROOT/http/live"

for mapping in "${links[@]}"; do
    relative_path=${mapping%%|*}
    target=${mapping#*|}
    destination="$PROJECT_ROOT/$relative_path"

    if [[ -L "$destination" && "$(readlink -- "$destination")" == "$target" ]]; then
        continue
    fi
    if [[ -L "$destination" ]]; then
        rm -- "$destination"
    fi
    ln -s -- "$target" "$destination"
    echo "Linked $relative_path -> $target"
done

missing=0
for mapping in "${links[@]}"; do
    relative_path=${mapping%%|*}
    destination="$PROJECT_ROOT/$relative_path"
    if [[ ! -e "$destination" ]]; then
        echo "Notice: link target is not present yet: $relative_path -> $(readlink -- "$destination")" >&2
        missing=$((missing + 1))
    fi
done

echo "HTTP compatibility links are in place ($missing target(s) currently absent)."
