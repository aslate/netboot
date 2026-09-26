#!/usr/bin/env bash
set -euo pipefail

# Back up pre-existing service configuration once, enable both units, install
# the project configuration, validate it, and activate the services.
# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

require_project_location
for command in caddy dnsmasq systemctl; do
    require_command "$command"
done
[[ -s "$PROJECT_ROOT/tftp/ipxe.efi" ]] || {
    echo "Missing $PROJECT_ROOT/tftp/ipxe.efi; install the bootstrap first." >&2
    exit 1
}
[[ -s "$PROJECT_ROOT/tftp/undionly.kpxe" ]] || {
    echo "Missing $PROJECT_ROOT/tftp/undionly.kpxe; install the BIOS bootstrap first." >&2
    exit 1
}

backup_once() {
    local source=$1 backup=$2
    if [[ -e "$source" && ! -e "$backup" ]]; then
        run_as_root cp -a "$source" "$backup"
        echo "Backed up $source to $backup"
    fi
}

backup_once /etc/dnsmasq.d/netboot.conf /etc/dnsmasq.d/netboot.conf.before-netboot
backup_once /etc/systemd/system/dnsmasq.service.d/netboot.conf /etc/systemd/system/dnsmasq.service.d/netboot.conf.before-netboot
backup_once /etc/caddy/Caddyfile /etc/caddy/Caddyfile.before-netboot

run_as_root systemctl enable caddy.service dnsmasq.service
run_as_root "$PROJECT_ROOT/scripts/apply-netboot-config.sh"
echo "Netboot service configuration installed and enabled."
