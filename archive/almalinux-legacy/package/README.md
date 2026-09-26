# AlmaLinux 10 — parked work

AlmaLinux remains an incomplete PXE experiment and is intentionally parked.
This package boundary identifies its source material without redesigning or
claiming to fix the boot handoff.

## Collected material

- `AlmaLinux-10-latest-x86_64-boot.iso` and `CHECKSUM` are the source media.
- `alma10-server-gui.ks` is the Alma-specific Kickstart.
- `boot.ipxe` is the current diagnostic iPXE entry.
- `prepare.sh` retains the existing Alma preparation workflow.
- `test-handoff.sh` retains the reversible handoff diagnostic.

## Preserved runtime state

- The extracted boot-ISO tree remains under `/srv/netboot/alma10` and is
  served at `/alma10/`.
- The existing Alma TFTP experiment remains under `/srv/netboot/tftp/alma10`.
- `/menu/almalinux.ipxe`, `/almalinux/boot.ipxe`, and `/kickstarts/` remain
  available through HTTP compatibility links.
- `http/live/` and generic TFTP bootstrap content remain untouched pending
  ownership review.

## Status

The kernel/initramfs handoff has not been treated as fixed by this migration.
Later Alma investigation must validate the client handoff before changing the
runtime layout or removing preserved experiment files.
