#!/usr/bin/env bash
set -euo pipefail

# Validate the repository-local deployment without systemd or /etc copies.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/config/netboot.env"

for command in caddy curl dnsmasq python3 ip ss; do
	command -v "$command" >/dev/null 2>&1 || {
		echo "Missing required command: $command" >&2
		exit 1
	}
done

"$ROOT/scripts/netbootctl" render
dnsmasq --test --conf-file="$NETBOOT_DNSMASQ_CONFIG_RUNTIME"
caddy validate --config "$NETBOOT_CADDY_CONFIG_RUNTIME" --adapter caddyfile
"$ROOT/scripts/netbootctl" status | tee "$NETBOOT_RUNTIME_ROOT/validation.status"
grep -Fq 'caddy    running' "$NETBOOT_RUNTIME_ROOT/validation.status"
grep -Fq 'dnsmasq  running' "$NETBOOT_RUNTIME_ROOT/validation.status"
[[ -s "$ROOT/tftp/$NETBOOT_UEFI_BOOTSTRAP" ]] || {
	echo "Missing UEFI iPXE bootstrap." >&2
	exit 1
}
[[ -s "$ROOT/tftp/$NETBOOT_BIOS_BOOTSTRAP" ]] || {
	echo "Missing Legacy BIOS iPXE bootstrap." >&2
	exit 1
}
ip -4 address show dev "$NETBOOT_INTERFACE" | grep -Fq "inet $NETBOOT_SERVER_IP/"
for port in "$NETBOOT_HTTP_PORT" "$NETBOOT_TFTP_PORT" "$NETBOOT_PXE_PROXY_PORT"; do
	ss -H -lntu | awk '{print $5}' | grep -Eq "[:.]$port$" || {
		echo "Expected listener for port $port was not found." >&2
		exit 1
	}
done
curl --fail --silent --show-error --head "$NETBOOT_IPXE_MENU_URL" >/dev/null

echo "Standalone validation passed: configuration, daemons, and HTTP menu are available."
