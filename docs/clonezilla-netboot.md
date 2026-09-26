# Clonezilla netboot reference

## Current target

Clonezilla Live `3.3.3-15` Debian amd64 is a working live-boot reference
package. The broader project reference matrix is maintained in
`docs/netboot-reference.md`.

The archive, checksum, preparation script, boot entry, and generated payloads
are kept together under the ignored package payload directory:

```text
packages/clonezilla/
├── package.conf
├── boot.ipxe
├── prepare.sh
├── clonezilla-live-3.3.3-15-amd64.zip
├── clonezilla-live-3.3.3-15-amd64.zip.sha256
├── filesystem.squashfs
├── initrd.img
└── vmlinuz
```

The package is exposed at `/clonezilla/` through the HTTP compatibility link.

The payloads are intentionally HTTP-served. TFTP contains only the small
UEFI iPXE bootstrap.

## Boot flow

```text
router DHCP
  -> dnsmasq proxy-DHCP
  -> TFTP /tftp/ipxe.efi
  -> HTTP /menu/main.ipxe
  -> HTTP /clonezilla/boot.ipxe
  -> HTTP Clonezilla vmlinuz + initrd.img + filesystem.squashfs
```

The menu currently defaults to CachyOS, but Clonezilla remains available as a
working utility target. AlmaLinux remains available as a parked diagnostic path.
Clonezilla has no restore or disk automation enabled.

## Apply the host configuration

Run this from the project directory on the CachyOS host when a visible sudo
prompt is available:

```bash
./scripts/apply-netboot-config.sh
```

That updates only the dnsmasq proxy-DHCP handoff, preserves the existing
interface and subnet, validates dnsmasq and Caddy, and restarts dnsmasq.

## Host validation

```bash
for path in \
  http/menu/main.ipxe \
  clonezilla/boot.ipxe \
  clonezilla/vmlinuz \
  clonezilla/initrd.img \
  clonezilla/filesystem.squashfs; do
  curl --fail --head "http://192.168.1.2/$path"
done

sudo journalctl -f -u dnsmasq.service -u caddy.service -o short-iso
```

The success boundary is the Clonezilla live environment. If the kernel and
initramfs download but Linux does not start, record that as the common
iPXE-to-Linux handoff boundary. If Linux starts but the live environment does
not, inspect the Clonezilla filesystem fetch and kernel arguments.
