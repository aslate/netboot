#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    exec sudo "$BASH" "$0" --root
fi

ROOT=/srv/netboot
SERVER_IP=192.168.1.2
MENU="$ROOT/packages/almalinux/boot.ipxe"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$ROOT/.guided-runbook/almalinux-live/backups/$STAMP"

install -d -m 0755 "$BACKUP" "$ROOT/packages/almalinux"
cp -a /etc/dnsmasq.d/netboot.conf "$BACKUP/netboot.conf"
if [[ -f "$MENU" ]]; then
    cp -a "$MENU" "$BACKUP/almalinux.ipxe"
fi

install -m 0644 /dev/stdin "$MENU" <<IPXE
#!ipxe
dhcp
initrd --name initrd.img http://$SERVER_IP/alma10/images/pxeboot/initrd.img
kernel http://$SERVER_IP/alma10/images/pxeboot/vmlinuz ip=dhcp initrd=initrd.img console=tty0 inst.text rd.debug
imgstat
sleep 2
boot
IPXE

curl --fail --silent --show-error --head \
    "http://127.0.0.1/menu/almalinux.ipxe"
curl --fail --silent --show-error --head \
    "http://127.0.0.1/almalinux/boot.ipxe"
curl --fail --silent --show-error --head \
    "http://127.0.0.1/alma10/images/pxeboot/vmlinuz"
curl --fail --silent --show-error --head \
    "http://127.0.0.1/alma10/images/pxeboot/initrd.img"
dnsmasq --test --conf-file=/etc/dnsmasq.d/netboot.conf
systemctl is-active dnsmasq caddy

echo "Minimal AlmaLinux handoff test installed."
echo "Backup: $BACKUP"
echo "Reboot the PXE client and capture the first Linux/initramfs output."
