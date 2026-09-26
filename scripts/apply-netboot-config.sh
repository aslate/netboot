#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/setup/_common.sh"
require_project_location
ROOT=$PROJECT_ROOT
TFTP_ROOT="$ROOT/tftp"
CONFIG_DIR="$ROOT/config"
DNSMASQ_CONFIG="$CONFIG_DIR/dnsmasq.conf"
CADDYFILE="$CONFIG_DIR/Caddyfile"
INSTALLED_DNSMASQ_CONFIG=/etc/dnsmasq.d/netboot.conf
INSTALLED_CADDYFILE=/etc/caddy/Caddyfile

if [[ ${EUID} -ne 0 ]]; then
    exec sudo "$BASH" "$0" "$@"
fi

install -d -m 0755 /etc/dnsmasq.d /etc/caddy
install -d -m 0755 "$TFTP_ROOT"
test -s "$TFTP_ROOT/ipxe.efi"
test -s "$TFTP_ROOT/undionly.kpxe"
test -s "$DNSMASQ_CONFIG"
test -s "$CADDYFILE"
chown -R dnsmasq:dnsmasq "$TFTP_ROOT"

install -m 0644 "$DNSMASQ_CONFIG" "$INSTALLED_DNSMASQ_CONFIG"
install -m 0644 "$CADDYFILE" "$INSTALLED_CADDYFILE"

if [[ $(detect_host_family) == arch ]]; then
    # Arch's vendor unit reads only /etc/dnsmasq.conf and its package does not
    # create /etc/dnsmasq.d.  Point the unit at the project-owned fragment so
    # the installed proxy-DHCP/TFTP configuration is actually started.
    install -d -m 0755 /etc/systemd/system/dnsmasq.service.d
    cat > /etc/systemd/system/dnsmasq.service.d/netboot.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/dnsmasq --keep-in-foreground --conf-file=/etc/dnsmasq.d/netboot.conf
EOF
    systemctl daemon-reload
fi

dnsmasq --test --conf-file="$INSTALLED_DNSMASQ_CONFIG"
caddy validate --config "$INSTALLED_CADDYFILE"
systemctl restart dnsmasq
systemctl reload-or-restart caddy
systemctl is-active dnsmasq
systemctl is-active caddy

echo "Applied and activated the netboot dnsmasq and Caddy configuration."
