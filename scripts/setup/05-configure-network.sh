#!/usr/bin/env bash
set -euo pipefail

# Apply the static address recorded in config/netboot.env. Prefer an existing
# persistent host network manager; the ip fallback is deliberately temporary.
# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

require_project_location
require_command ip
require_command grep

if [[ ! -d "/sys/class/net/$NETBOOT_INTERFACE" ]]; then
	echo "Network interface '$NETBOOT_INTERFACE' does not exist." >&2
	exit 1
fi

if command -v nmcli >/dev/null 2>&1; then
	connection="$NETBOOT_NETWORK_CONNECTION"
	if ! nmcli -t -f NAME connection show | grep -Fxq "$connection"; then
		run_as_root nmcli connection add type ethernet ifname "$NETBOOT_INTERFACE" con-name "$connection"
	fi
	run_as_root nmcli connection modify "$connection" \
		connection.interface-name "$NETBOOT_INTERFACE" \
		ipv4.method manual ipv4.addresses "$NETBOOT_SERVER_ADDRESS" \
		ipv4.gateway "$NETBOOT_GATEWAY" ipv4.dns "$NETBOOT_DNS" \
		connection.autoconnect yes
	run_as_root nmcli connection up "$connection"
	echo "Configured persistent NetworkManager connection '$connection'."
	exit 0
fi

if command -v networkctl >/dev/null 2>&1; then
	file="/etc/systemd/network/10-netboot-$NETBOOT_INTERFACE.network"
	run_as_root install -d -m 0755 /etc/systemd/network
	run_as_root tee "$file" >/dev/null <<EOF
[Match]
Name=$NETBOOT_INTERFACE

[Network]
Address=$NETBOOT_SERVER_ADDRESS
Gateway=$NETBOOT_GATEWAY
DNS=$NETBOOT_DNS
EOF
	run_as_root networkctl reload
	run_as_root networkctl reconfigure "$NETBOOT_INTERFACE"
	echo "Configured persistent systemd-networkd profile '$file'."
	exit 0
fi

run_as_root ip link set dev "$NETBOOT_INTERFACE" up
run_as_root ip address replace "$NETBOOT_SERVER_ADDRESS" dev "$NETBOOT_INTERFACE"
echo "Applied $NETBOOT_SERVER_ADDRESS to $NETBOOT_INTERFACE temporarily."
echo "No persistent NetworkManager or systemd-networkd backend was found; configure persistence with the host network manager."
