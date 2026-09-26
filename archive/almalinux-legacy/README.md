# Superseded AlmaLinux investigation

This directory preserves the pre-reimplementation AlmaLinux work. The files
under `package/` are historical evidence and are not an active boot path.

The old attempt was correct to identify the AlmaLinux boot ISO as a network
installer, retain `images/install.img`, use the remote BaseOS kickstart tree,
verify the Alma checksum format, and move the large initramfs away from TFTP.

It was unnecessarily broad in building a GRUB/TFTP tree, installing host GRUB
and iPXE tooling, rewriting `/etc/dnsmasq.d/netboot.conf`, and maintaining
several duplicate serving paths. Its diagnostic iPXE recipe also omitted the
stage2, repository, and Kickstart arguments. The clean implementation uses the
working Fedora Anaconda handoff directly: package-local HTTP kernel/initramfs,
explicit network setup, local HTTP stage2, remote `inst.repo`, and package-local
Kickstart.

The old extracted runtime trees remain available separately until the clean
client boot has been confirmed and their removal can be validated.
