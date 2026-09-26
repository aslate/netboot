# AlmaLinux 10.2 installer

This is the Anaconda implementation derived from the working Fedora installer
package. It uses the AlmaLinux 10.2 boot ISO for the kernel, initramfs, and
installer stage, then obtains packages from the BaseOS, AppStream, Extras,
CRB, and EPEL repositories used by AlmaLinux's official KDE live-media recipe.

`prepare.sh` verifies the retained boot ISO, extracts only the files required
for HTTP booting, and removes its temporary extraction directory on exit. The
package is exposed through `/almalinux/` by the existing HTTP compatibility
link. Its iPXE recipe chains the host's custom GRUB EFI loader, avoiding the
iPXE EFI kernel handoff that stalls with Alma's kernel on the target firmware.

The previous GRUB/TFTP experiment is retained under
`archive/almalinux-legacy/package/` for comparison. It is not part of this
boot path and must not be used as the active implementation.

The Kickstart is intentionally destructive for the test machine: it selects
the first non-removable writable disk, creates a GPT/UEFI LVM layout, installs
KDE Plasma, creates `aslate` with the temporary password `changeme` and the
project's SSH key, excludes the office suites, and masks Avahi services after
installation.
