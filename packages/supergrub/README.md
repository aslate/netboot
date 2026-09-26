# Super Grub2 Disk

This package follows the current netboot.xyz Super Grub2 implementation:

- UEFI clients load `supergrub2-classic-x86_64.efi` from the netboot.xyz asset
  mirror.
- Legacy-BIOS clients load the Super Grub2 hybrid ISO through the existing
  SystemRescue `memdisk` payload.

The payloads remain upstream-hosted; this package contains the local iPXE
platform selection and does not duplicate the large ISO or EFI executable.
