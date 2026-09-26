#!/usr/bin/env bash
set -euo pipefail

# Detect and configure the host's existing firewall backend. The project does
# not install or select a firewall backend as part of its service setup.
# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

require_project_location
for command in awk grep; do require_command "$command"; done

mode=add
assume_yes=0
enable_backend=0
while (($#)); do
	case "$1" in
	"") ;;
	--remove) mode=remove ;;
	--yes) assume_yes=1 ;;
	--enable) enable_backend=1 ;;
	*)
		echo "Usage: $0 [--enable] [--yes|--remove]" >&2
		exit 2
		;;
	esac
	shift
done

backend="${NETBOOT_FIREWALL_BACKEND:-auto}"
ufw_active=0
firewalld_active=0
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -Fq 'Status: active'; then ufw_active=1; fi
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet firewalld.service 2>/dev/null; then firewalld_active=1; fi

if [[ "$backend" == auto ]]; then
	if ((ufw_active && firewalld_active)); then
		echo "Both UFW and firewalld are active; set NETBOOT_FIREWALL_BACKEND explicitly." >&2
		exit 1
	elif ((ufw_active)); then
		backend=ufw
	elif ((firewalld_active)); then
		backend=firewalld
	elif command -v ufw >/dev/null 2>&1 && ! command -v firewall-cmd >/dev/null 2>&1; then
		backend=ufw
	elif command -v firewall-cmd >/dev/null 2>&1 && ! command -v ufw >/dev/null 2>&1; then
		backend=firewalld
	else
		echo "No unambiguous active firewall backend detected. Activate UFW or firewalld, or set NETBOOT_FIREWALL_BACKEND." >&2
		exit 1
	fi
fi
[[ "$backend" == ufw || "$backend" == firewalld ]] || {
	echo "Unsupported firewall backend: $backend" >&2
	exit 1
}

if [[ "$backend" == ufw ]]; then
	require_command ufw
	if ! ((ufw_active)); then
		if ((enable_backend)); then
			echo "Enabling UFW may alter remote reachability. Ensure SSH access is allowed first."
			run_as_root ufw --force enable
		else
			echo "UFW is installed but inactive; run 'ufw enable' or use --enable." >&2
			exit 1
		fi
	fi
else
	require_command firewall-cmd
	require_command systemctl
	if ! ((firewalld_active)); then
		if ((enable_backend)); then
			echo "Enabling firewalld may alter remote reachability. Ensure SSH access is allowed first."
			run_as_root systemctl enable --now firewalld.service
		else
			echo "firewalld is installed but inactive; use --enable from a safe console." >&2
			exit 1
		fi
	fi
fi

ask() {
	local prompt=$1
	((assume_yes)) && return 0
	read -r -p "$prompt [y/N] " answer
	[[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

ufw_rule() {
	local action=$1 direction=$2 interface=$3 source=$4 port=$5 protocol=$6
	if [[ "$action" == add ]]; then
		if [[ -n "$source" ]]; then
			run_as_root ufw allow "$direction" on "$interface" from "$source" to any port "$port" proto "$protocol"
		else
			run_as_root ufw allow "$direction" on "$interface" to any port "$port" proto "$protocol"
		fi
	else
		if [[ -n "$source" ]]; then
			run_as_root ufw delete allow "$direction" on "$interface" from "$source" to any port "$port" proto "$protocol" || true
		else
			run_as_root ufw delete allow "$direction" on "$interface" to any port "$port" proto "$protocol" || true
		fi
	fi
}

firewalld_rule() {
	local action=$1 rule=$2 zone
	zone=$(firewall-cmd --get-zone-of-interface="$NETBOOT_INTERFACE" 2>/dev/null || true)
	[[ -n "$zone" && "$zone" != "no zone" ]] || zone=$(firewall-cmd --get-default-zone)
	if [[ "$action" == add ]]; then
		firewall-cmd --permanent --zone="$zone" --query-rich-rule="$rule" >/dev/null || run_as_root firewall-cmd --permanent --zone="$zone" --add-rich-rule="$rule"
	elif firewall-cmd --permanent --zone="$zone" --query-rich-rule="$rule" >/dev/null; then
		run_as_root firewall-cmd --permanent --zone="$zone" --remove-rich-rule="$rule"
	fi
}

apply_service() {
	local service=$1 prompt=$2
	if [[ "$mode" == add ]] && ! ask "$prompt"; then
		echo "Skipped $service."
		return
	fi
	if [[ "$mode" == remove ]] && ! ((assume_yes)) && ! ask "Remove $service firewall rules?"; then
		echo "Kept $service."
		return
	fi
	local action=$mode
	if [[ "$backend" == ufw ]]; then
		case "$service" in
		http) ufw_rule "$action" in "$NETBOOT_INTERFACE" "$NETBOOT_SUBNET" "$NETBOOT_HTTP_PORT" tcp ;;
		tftp) ufw_rule "$action" in "$NETBOOT_INTERFACE" "$NETBOOT_SUBNET" "$NETBOOT_TFTP_PORT" udp ;;
		dhcp)
			ufw_rule "$action" in "$NETBOOT_INTERFACE" "" 67 udp
			ufw_rule "$action" out "$NETBOOT_INTERFACE" "" 68 udp
			ufw_rule "$action" in "$NETBOOT_INTERFACE" "$NETBOOT_SUBNET" "$NETBOOT_PXE_PROXY_PORT" udp
			;;
		esac
	else
		case "$service" in
		http) firewalld_rule "$action" "rule family=ipv4 source address=$NETBOOT_SUBNET port port=$NETBOOT_HTTP_PORT protocol=tcp accept" ;;
		tftp) firewalld_rule "$action" "rule family=ipv4 source address=$NETBOOT_SUBNET port port=$NETBOOT_TFTP_PORT protocol=udp accept" ;;
		dhcp)
			firewalld_rule "$action" "rule family=ipv4 port port=67 protocol=udp accept"
			firewalld_rule "$action" "rule family=ipv4 source address=$NETBOOT_SUBNET port port=$NETBOOT_PXE_PROXY_PORT protocol=udp accept"
			;;
		esac
	fi
}

echo "Firewall backend: $backend"
apply_service http "Enable HTTP (TCP $NETBOOT_HTTP_PORT)?"
apply_service tftp "Enable TFTP (UDP $NETBOOT_TFTP_PORT)?"
apply_service dhcp "Enable DHCP/PXE (UDP 67 and $NETBOOT_PXE_PROXY_PORT)?"
[[ "$backend" == firewalld ]] && run_as_root firewall-cmd --reload
echo "Firewall rules ${mode} operation completed using $backend."
