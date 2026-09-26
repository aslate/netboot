#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    exec sudo "$BASH" "$0" --root
fi

ROOT=/srv/netboot
SERVER_IP=192.168.1.2
ISO_DIR="$ROOT/packages/almalinux"
ISO="$ISO_DIR/AlmaLinux-10-latest-x86_64-boot.iso"
CHECKSUM="$ISO_DIR/CHECKSUM"
MOUNT_DIR=/mnt/alma10
ISO_URL=https://repo.almalinux.org/almalinux/10/isos/x86_64/AlmaLinux-10-latest-x86_64-boot.iso
CHECKSUM_URL=https://repo.almalinux.org/almalinux/10/isos/x86_64/CHECKSUM
REMOTE_REPO=https://repo.almalinux.org/almalinux/10/BaseOS/x86_64/kickstart
KICKSTART="$ROOT/packages/almalinux/alma10-server-gui.ks"
TARGET_USER="${SUDO_USER:-aslate}"
mounted=0

cleanup() {
    if (( mounted )); then
        umount "$MOUNT_DIR" || true
    fi
}
trap cleanup EXIT

cd "$ROOT"
command -v curl >/dev/null
command -v mount >/dev/null
command -v sha256sum >/dev/null
command -v bsdtar >/dev/null
command -v pacman >/dev/null
command -v grub-file >/dev/null
command -v grub-mkimage >/dev/null

pacman -S --needed --noconfirm grub ipxe
command -v grub-mknetdir >/dev/null

install -d -m 0755 "$ISO_DIR" "$ROOT/alma10" "$ROOT/tftp" "$ROOT/packages/almalinux"
test -s "$KICKSTART"

if [[ ! -s "$CHECKSUM" ]]; then
    curl --fail --location --retry 3 --output "$CHECKSUM" "$CHECKSUM_URL"
else
    echo "Using existing checksum file: $CHECKSUM"
fi
if [[ ! -s "$ISO" ]]; then
    curl --fail --location --retry 3 --output "$ISO" "$ISO_URL"
else
    echo "Using existing ISO: $ISO"
fi

expected="$(awk -v f="$(basename "$ISO")" \
    '$0 ~ "^SHA256 \\(" f "\\) = " {print $NF; exit}' "$CHECKSUM")"
[[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] || {
    echo "Could not find a SHA-256 entry for $(basename "$ISO") in $CHECKSUM" >&2
    exit 1
}
actual="$(sha256sum "$ISO" | awk '{print $1}')"
[[ "$actual" == "$expected" ]] || {
    echo "Checksum mismatch for $ISO" >&2
    exit 1
}

install -d -m 0755 "$MOUNT_DIR"
mount -o loop,ro "$ISO" "$MOUNT_DIR"
mounted=1
for required in \
    "$MOUNT_DIR/EFI/BOOT/BOOTX64.EFI" \
    "$MOUNT_DIR/EFI/BOOT/grubx64.efi" \
    "$MOUNT_DIR/images/pxeboot/vmlinuz" \
    "$MOUNT_DIR/images/pxeboot/initrd.img" \
    "$MOUNT_DIR/images/install.img"; do
    [[ -f "$required" ]] || { echo "ISO lacks $required" >&2; exit 1; }
done

# Caddy serves this complete boot-ISO tree. It supplies images/install.img
# for Anaconda stage2; the package repository remains remote.
bsdtar -xpf "$ISO" -C "$ROOT/alma10"

install -d -m 0755 "$ROOT/tftp/images/pxeboot"
install -m 0644 /usr/share/ipxe/x86_64/ipxe.efi "$ROOT/tftp/ipxe.efi"
install -m 0644 "$MOUNT_DIR/images/pxeboot/vmlinuz" \
    "$ROOT/tftp/images/pxeboot/vmlinuz"
install -m 0644 "$MOUNT_DIR/images/pxeboot/initrd.img" \
    "$ROOT/tftp/images/pxeboot/initrd.img"

grub-mknetdir \
    --net-directory="$ROOT/tftp" \
    --subdir=boot/grub \
    -d /usr/lib/grub/x86_64-efi

test -s "$ROOT/tftp/boot/grub/x86_64-efi/core.efi"
install -m 0644 /dev/stdin "$ROOT/tftp/boot/grub/grub.cfg" <<GRUB
set default=0
set timeout=5

menuentry 'Install AlmaLinux 10' {
    linux (http,$SERVER_IP)/alma10/images/pxeboot/vmlinuz ip=dhcp inst.stage2=http://$SERVER_IP/alma10/ inst.repo=$REMOTE_REPO inst.ks=http://$SERVER_IP/kickstarts/alma10-server-gui.ks
    initrd (http,$SERVER_IP)/alma10/images/pxeboot/initrd.img
}
GRUB

# The generic grub-mknetdir image is correct for firmware that preserves the
# PXE network context, but some UEFI implementations hand the EFI image off
# without a usable GRUB network device.  Embed a small bootstrap that repeats
# DHCP and pins the TFTP server/prefix before loading normal.mod.  This keeps
# the documented GRUB network layout while avoiding a rescue prompt before
# GRUB has made its first TFTP request for a module or grub.cfg.
install -m 0644 /dev/stdin "$ROOT/tftp/boot/grub/netboot-bootstrap.cfg" <<GRUBBOOT
insmod efinet
insmod net
insmod tftp
insmod http
net_dhcp
set net_default_server=$SERVER_IP
set root=(tftp,$SERVER_IP)
set prefix=(tftp,$SERVER_IP)/boot/grub
insmod normal
normal
GRUBBOOT

grub-mkimage \
    -O x86_64-efi \
    -d /usr/lib/grub/x86_64-efi \
    -p "(tftp,$SERVER_IP)/boot/grub" \
    -c "$ROOT/tftp/boot/grub/netboot-bootstrap.cfg" \
    -o "$ROOT/tftp/boot/grub/x86_64-efi/core.efi" \
    efinet net tftp http normal configfile linux echo terminal terminfo gettext

grub-file --is-x86_64-efi "$ROOT/tftp/boot/grub/x86_64-efi/core.efi"
install -m 0644 "$ROOT/tftp/boot/grub/grub.cfg" \
    "$ROOT/alma10/EFI/BOOT/grub.cfg"

install -m 0644 /dev/stdin "$ROOT/packages/almalinux/boot.ipxe" <<IPXE
#!ipxe
dhcp
initrd --name initrd.img http://$SERVER_IP/alma10/images/pxeboot/initrd.img
kernel http://$SERVER_IP/alma10/images/pxeboot/vmlinuz ip=dhcp initrd=initrd.img inst.stage2=http://$SERVER_IP/alma10/ inst.repo=$REMOTE_REPO inst.ks=http://$SERVER_IP/kickstarts/alma10-server-gui.ks
imgstat
sleep 2
boot
IPXE

chown -R dnsmasq:dnsmasq "$ROOT/tftp"

install -m 0644 /dev/stdin /etc/dnsmasq.d/netboot.conf <<DNSMASQ
# AlmaLinux 10 UEFI iPXE chainload via proxy-DHCP
interface=eno1
bind-interfaces
port=0
dhcp-range=192.168.1.0,proxy
log-dhcp
dhcp-match=set:ipxe,175
dhcp-match=set:efi64,option:client-arch,7
dhcp-match=set:efi64,option:client-arch,9
dhcp-boot=tag:!ipxe,tag:efi64,ipxe.efi,,$SERVER_IP
pxe-service=tag:!ipxe,tag:efi64,7,"AlmaLinux 10 UEFI iPXE",ipxe.efi,$SERVER_IP
    dhcp-boot=tag:ipxe,http://$SERVER_IP/almalinux/boot.ipxe,,0.0.0.1
enable-tftp
tftp-root=$ROOT/tftp
tftp-secure
DNSMASQ

dnsmasq --test --conf-file=/etc/dnsmasq.d/netboot.conf
systemctl restart dnsmasq

curl --fail --silent --show-error --head \
    "http://127.0.0.1/alma10/images/install.img"
curl --fail --silent --show-error --head \
    "http://127.0.0.1/alma10/images/pxeboot/vmlinuz"
curl --fail --silent --show-error --head \
    "http://127.0.0.1/kickstarts/alma10-server-gui.ks"
curl --fail --silent --show-error --head \
    "http://127.0.0.1/almalinux/boot.ipxe"
curl --fail --silent --show-error --head "$REMOTE_REPO/.treeinfo"
test -s "$ROOT/tftp/ipxe.efi"
test -s "$ROOT/packages/almalinux/boot.ipxe"
test -s "$ROOT/tftp/boot/grub/x86_64-efi/core.efi"
test -s "$ROOT/tftp/boot/grub/grub.cfg"
test -s "$ROOT/tftp/images/pxeboot/vmlinuz"
test -s "$ROOT/tftp/images/pxeboot/initrd.img"
systemctl is-active dnsmasq caddy

chown -R "$TARGET_USER":"$TARGET_USER" \
    "$ROOT/.guided-runbook/almalinux-live" "$ROOT/packages/almalinux"
runuser -u "$TARGET_USER" -- git -C "$ROOT" add \
    .gitignore .guided-runbook/almalinux-live \
    packages/almalinux/alma10-server-gui.ks packages/almalinux/prepare.sh \
    packages/almalinux/test-handoff.sh
runuser -u "$TARGET_USER" -- git -C "$ROOT" commit \
    -m "Use documented AlmaLinux UEFI GRUB PXE path" || true
echo "AlmaLinux GRUB PXE phase completed."
