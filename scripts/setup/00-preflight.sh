#!/usr/bin/env bash
set -euo pipefail

# Read-only checks for the fixed project location, host platform, network, and
# payloads required before service installation.
# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

require_project_location
require_supported_host

for command in bash ip grep find readlink; do
    require_command "$command"
done

[[ -d "$PROJECT_ROOT/config" ]] || { echo "Missing $PROJECT_ROOT/config" >&2; exit 1; }
[[ -d "$PROJECT_ROOT/http" ]] || { echo "Missing $PROJECT_ROOT/http" >&2; exit 1; }
[[ -d "$PROJECT_ROOT/tftp" ]] || { echo "Missing $PROJECT_ROOT/tftp" >&2; exit 1; }
[[ -s "$PROJECT_ROOT/config/dnsmasq.conf" ]] || { echo "Missing dnsmasq configuration." >&2; exit 1; }
[[ -s "$PROJECT_ROOT/config/Caddyfile" ]] || { echo "Missing Caddy configuration." >&2; exit 1; }

[[ -d "/sys/class/net/$NETBOOT_INTERFACE" ]] || {
    echo "Network interface '$NETBOOT_INTERFACE' does not exist." >&2
    echo "Adapt config/netboot.env and the static service configuration before continuing." >&2
    exit 1
}

ip -4 address show dev "$NETBOOT_INTERFACE" | grep -Fq "inet $NETBOOT_SERVER_IP/" || {
    echo "$NETBOOT_INTERFACE does not currently own $NETBOOT_SERVER_IP." >&2
    echo "Configure a persistent static address before enabling netboot services." >&2
    exit 1
}

grep -Fq "interface=$NETBOOT_INTERFACE" "$PROJECT_ROOT/config/dnsmasq.conf" || {
    echo "config/dnsmasq.conf does not target $NETBOOT_INTERFACE." >&2
    exit 1
}
grep -Fq "$NETBOOT_SERVER_IP" "$PROJECT_ROOT/config/dnsmasq.conf" || {
    echo "config/dnsmasq.conf does not reference $NETBOOT_SERVER_IP." >&2
    exit 1
}

broken_links="$(find -L "$PROJECT_ROOT/http" -type l -print)"
if [[ -n "$broken_links" ]]; then
    echo "Broken HTTP compatibility links:" >&2
    echo "$broken_links" >&2
    exit 1
fi

if [[ ! -s "$PROJECT_ROOT/tftp/ipxe.efi" ]]; then
    echo "Notice: tftp/ipxe.efi is absent; run the bootstrap installation helper."
fi
if [[ ! -s "$PROJECT_ROOT/tftp/undionly.kpxe" ]]; then
    echo "Notice: tftp/undionly.kpxe is absent; place undionly.kpxe in the project root and run the bootstrap installation helper."
fi

cat <<EOF
Preflight passed.
  project:   $PROJECT_ROOT
  interface: $NETBOOT_INTERFACE
  address:   $NETBOOT_SERVER_IP
  subnet:    $NETBOOT_SUBNET

This configuration assumes the existing router remains the authoritative DHCP
server. Do not enable another ordinary DHCP pool on the same LAN.
EOF
