#!/usr/bin/env bash
set -euo pipefail

# Validate installed configuration, service state, bootstrap availability, and
# local HTTP menu delivery without changing the host.
# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

require_project_location
for command in caddy curl dnsmasq systemctl; do
    require_command "$command"
done

[[ -s "$PROJECT_ROOT/tftp/ipxe.efi" ]] || { echo "Missing iPXE bootstrap." >&2; exit 1; }
[[ -s "$PROJECT_ROOT/tftp/undionly.kpxe" ]] || { echo "Missing Legacy-BIOS iPXE bootstrap." >&2; exit 1; }
[[ -s /etc/dnsmasq.d/netboot.conf ]] || { echo "dnsmasq config is not installed." >&2; exit 1; }
[[ -s /etc/caddy/Caddyfile ]] || { echo "Caddy config is not installed." >&2; exit 1; }

run_as_root dnsmasq --test --conf-file=/etc/dnsmasq.d/netboot.conf
run_as_root caddy validate --config /etc/caddy/Caddyfile
run_as_root systemctl is-enabled caddy.service dnsmasq.service
run_as_root systemctl is-active caddy.service dnsmasq.service
curl --fail --silent --show-error --head http://127.0.0.1/menu/main.ipxe >/dev/null

echo "Host validation passed: configuration, services, iPXE, and HTTP menu are available."
