# Netboot server

This repository contains the project-owned configuration, boot menus, package
recipes, and documentation for the netboot server. The authoritative operating
model and reference matrix are in
[`docs/netboot-reference.md`](docs/netboot-reference.md).

## Current architecture

```text
PXE client
  -> router DHCP on the existing LAN
  -> dnsmasq proxy-DHCP on eno1 / 192.168.1.2
  -> UDP/4011 PXE metadata
  -> TFTP /srv/netboot/tftp/ipxe.efi
  -> HTTP Caddy /srv/netboot/http/menu/main.ipxe
  -> package boot recipe and HTTP-served live payload
```

The router remains the address-giving DHCP server. dnsmasq supplies PXE
metadata and secure TFTP on `eno1`; Caddy supplies the menu and all substantial
boot payloads over HTTP.

## Working targets

- Clonezilla Live 3.3.3-15
- GParted Live 1.8.1-6
- Debian Live Standard 13.7.0
- CachyOS Live 260809
- Rescuezilla 2.6.2
- Fedora Workstation 44
- Fedora Sway Live 44 (prepared; client boot pending)
- Fedora KDE Installer 44

The menu is at `http://192.168.1.2/menu/main.ipxe` and defaults to Fedora Sway
Live 44 after a ten-second timeout for current testing. The other targets remain
available, along with the parked AlmaLinux diagnostic entry, an iPXE shell, and
reboot.

## Parked work

AlmaLinux is an incomplete Anaconda/netinstall experiment, not a reference
package. Its source material, extracted boot tree, TFTP experiment, Kickstart,
and diagnostic scripts are retained for later investigation. See
[`packages/almalinux/README.md`](packages/almalinux/README.md).

## Project layout

| Directory | Responsibility |
| --- | --- |
| `config/` | Project-owned dnsmasq and Caddy configuration sources |
| `http/` | Caddy document root: menu and compatibility links into packages |
| `tftp/` | dnsmasq TFTP root; the active flow requires the small `ipxe.efi` bootstrap |
| `packages/` | Boot-target-specific source metadata, recipes, and prepared runtime files |
| `scripts/` | Server-wide configuration and administration scripts |
| `docs/` | Architecture, reference, operational, and historical troubleshooting notes |
| `archive/` | Material deliberately retained as obsolete or historical reference |
| `.guided-runbook/` | Tracked execution context from earlier infrastructure and image work |

Large downloaded images and extracted payloads are runtime artifacts and are
ignored by Git. Package metadata, boot recipes, preparation scripts, checksum
material, and relevant signatures are maintained in the repository.

## Setting up another host

[`config/netboot.env`](config/netboot.env) is the centralized record of host
settings and service configuration. The service configuration and boot recipes
retain their static values; see the host guide before changing site values.

See [`docs/host-setup.md`](docs/host-setup.md) for the complete migration,
network, package, service, and firewall procedure. The common entry points are:

```bash
make preflight
make setup                 # leaves firewall management to the host
make setup-with-firewall   # explicitly enables and configures firewalld
make links                 # recreate HTTP compatibility symlinks
make validate
```

Run `make help` for all setup and day-to-day operations. A Git clone does not
contain the ignored ISO and extracted runtime payloads, so copy those from the
old server or rebuild them with the package preparation recipes.

## Administration

Use the repository-local control CLI. Run it without arguments for an
interactive menu, or use a subcommand for scripts and direct operation:

```bash
./scripts/netbootctl
./scripts/netbootctl start
./scripts/netbootctl stop
./scripts/netbootctl reload
./scripts/netbootctl logs
./scripts/netbootctl tui
```

The CLI requests `sudo` only for the selected privileged operation. `logs`
shows the latest 100 dnsmasq and Caddy journal entries and follows new output;
press Ctrl-C to stop. Options after `tui` are passed to the monitor, for
example `./scripts/netbootctl tui --interface eno1 --history 150`.

The underlying configuration command remains available for troubleshooting:

```bash
sudo ./scripts/apply-netboot-config.sh
```

Validate services and follow the request sequence directly with:

```bash
sudo systemctl is-active dnsmasq caddy
sudo journalctl -f -u dnsmasq.service -u caddy.service -o short-iso
```

Keep TFTP limited to the small bootstrap wherever the selected boot technology
allows it; serve kernels, initramfs files, installers, and live filesystems over
HTTP.

## Network-boot visibility TUI

Run the passive monitor through the control CLI from a terminal on the netboot
host:

```bash
./scripts/netbootctl tui
```

It watches `eno1`, the existing dnsmasq and Caddy journals, and displays PXE
sessions, TFTP/HTTP transfers, best-effort byte progress, completed-file ticks,
and a rolling transfer log. Press `q` to exit. The monitor is observational and
does not change the dnsmasq or Caddy configuration.

Progress is passive rather than authoritative: the current HTTP service is
plaintext, so the monitor can count visible TCP bytes and use response sizes;
retransmissions are de-duplicated. Missing packet-capture privileges, encrypted
traffic, or incomplete headers produce an indeterminate bar with a warning.
The interface and paths can be overridden, for example:

```bash
./scripts/netbootctl tui --interface eno1 --history 150
```
