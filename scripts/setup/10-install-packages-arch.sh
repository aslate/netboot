#!/usr/bin/env bash
set -euo pipefail

# Install the Arch/CachyOS packages required by the server and preparation
# recipes. This does not enable services or alter the firewall.
# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

require_project_location
require_arch_host
require_command pacman

run_as_root pacman -S --needed \
    bash \
    caddy \
    coreutils \
    curl \
    diffutils \
    dnsmasq \
    findutils \
    firewalld \
    gawk \
    gzip \
    grep \
    iproute2 \
    ipxe \
    libarchive \
    python \
    procps-ng \
    sed \
    sudo \
    systemd \
    unzip \
    xorriso \
    zstd

echo "Host packages installed. No services or firewall rules were enabled."
