# Proxmox VE netboot

This package is prepared for a Proxmox VE installer ISO supplied locally as
`proxmox-ve_9.2-1.iso`. `SHA256SUMS` records the pinned SHA-256 of the
supplied ISO; replace it with the upstream checksum file when available.

Proxmox VE is an installer ISO rather than a Debian live-boot or Archiso
image. The preparation step follows Proxmox's PXE-compatible layout: it
extracts `/boot/linux26` and `/boot/initrd.img`, recompresses the initramfs to
gzip, removes `/boot` from a serving copy of the ISO, and loads the initramfs
and ISO together through iPXE. This avoids the installer waiting for a local
CD device after a whole-ISO `sanboot`.

The ISO was supplied locally. Preparation requires `xorriso` and `zstd`;
client boot validation remains pending until the PXE-compatible files are
prepared and tested.
