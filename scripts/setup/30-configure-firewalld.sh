#!/usr/bin/env bash
set -euo pipefail

# Add or remove source-scoped netboot rules in the firewalld zone associated
# with the PXE interface. Use --enable only from a local/console session: it
# may change remote reachability when firewalld was previously inactive.
# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

require_project_location
require_command firewall-cmd
require_command systemctl

mode=add
enable_firewalld=0
case "${1:-}" in
    "") ;;
    --enable) enable_firewalld=1 ;;
    --remove) mode=remove ;;
    *) echo "Usage: $0 [--enable|--remove]" >&2; exit 2 ;;
esac

if ! systemctl is-active --quiet firewalld.service; then
    if (( enable_firewalld )); then
        echo "Enabling firewalld. Ensure SSH or console access is permitted by the default zone."
        run_as_root systemctl enable --now firewalld.service
    else
        echo "firewalld is inactive; no rules were changed." >&2
        echo "Start it safely, or run '$0 --enable' from a local console." >&2
        exit 1
    fi
fi

zone="$(firewall-cmd --get-zone-of-interface="$NETBOOT_INTERFACE" 2>/dev/null || true)"
if [[ -z "$zone" || "$zone" == "no zone" ]]; then
    zone="$(firewall-cmd --get-default-zone)"
fi

rules=(
    "rule family=ipv4 source address=$NETBOOT_SUBNET service name=dhcp accept"
    "rule family=ipv4 source address=$NETBOOT_SUBNET service name=tftp accept"
    "rule family=ipv4 source address=$NETBOOT_SUBNET service name=http accept"
    "rule family=ipv4 source address=$NETBOOT_SUBNET port port=4011 protocol=udp accept"
)

for rule in "${rules[@]}"; do
    if [[ "$mode" == add ]]; then
        if ! firewall-cmd --permanent --zone="$zone" --query-rich-rule="$rule" >/dev/null; then
            run_as_root firewall-cmd --permanent --zone="$zone" --add-rich-rule="$rule"
        fi
    elif firewall-cmd --permanent --zone="$zone" --query-rich-rule="$rule" >/dev/null; then
        run_as_root firewall-cmd --permanent --zone="$zone" --remove-rich-rule="$rule"
    fi
done

run_as_root firewall-cmd --reload
if [[ "$mode" == add ]]; then
    action=added
else
    action=removed
fi
echo "Firewalld rules $action in zone '$zone' for source $NETBOOT_SUBNET."
