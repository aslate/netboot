# AlmaLinux Live KDE 10.2

This package uses the official x86_64 AlmaLinux 10.2 KDE Live ISO. Its boot
layout matches the Fedora Live family: the ISO contains a kernel and initramfs
under `images/pxeboot/` and a dracut `LiveOS/squashfs.img` live root.

`prepare.sh` verifies the retained ISO, extracts those three HTTP-served
resources, and cleans its temporary stage. `boot.ipxe` clears the chained menu
images and chains the package-local GRUB EFI loader, avoiding iPXE's kernel
executor. Its diagnostic GRUB configuration uses
`root=live:http://.../squashfs.img`, `rd.live.image`, and DHCP.

This is deliberately separate from `packages/almalinux/`, the Anaconda
installer implementation. The retained `grubx64.efi` and `grub.cfg` are
inactive diagnostics; the live entry no longer chains GRUB. The earlier
zero-byte/partial files under `http/live/` are historical and are not used by
this package.
