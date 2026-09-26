#!/usr/bin/env bash
set -euo pipefail

# Resolve every package before starting an install transaction. DNF 5 repoquery
# includes packages available for reinstall, even when already installed.
# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"
require_project_location
require_fedora_host
require_command dnf

packages=(
    bash bsdtar caddy coreutils curl diffutils dnsmasq findutils firewalld
    gawk gzip grep iproute ipxe-bootimgs-x86 libselinux-utils
    policycoreutils policycoreutils-python-utils python3 sed sudo systemd
    unzip xorriso zstd
)

if ! available=$(dnf repoquery --available --queryformat='%{name}' "${packages[@]}"); then
    echo "DNF package lookup failed; no install was attempted." >&2
    exit 1
fi

mapfile -t available_names <<< "$available"
missing=()
for package in "${packages[@]}"; do
    found=0
    for name in "${available_names[@]}"; do
        if [[ "$name" == "$package" ]]; then
            found=1
            break
        fi
    done
    if (( ! found )); then
        missing+=("$package")
    fi
done
if (( ${#missing[@]} )); then
    printf 'Missing Fedora package provider: %s\n' "${missing[@]}" >&2
    echo "No install was attempted." >&2
    exit 1
fi

run_as_root dnf install -y "${packages[@]}"
echo "Host packages installed. No services or firewall rules were enabled."
