# Netboot host setup

This guide rebuilds the host-side services after moving this project to an
Arch Linux or CachyOS machine. The supplied configuration is intentionally
site-specific: it expects `/srv/netboot`, interface `eno1`, server address
`192.168.1.2/24`, and LAN `192.168.1.0/24`.

`config/netboot.env` is the centralized record of host identity, service
ports, roots, standalone runtime paths, bootstraps, and configuration sources.
The repository-local renderer expands explicit placeholders without executing
template contents or writing service configuration into `/etc`.

The existing router must remain the authoritative DHCP server. dnsmasq runs
only as a proxy-DHCP/TFTP service and must not be given an ordinary address
pool on this LAN.

For an isolated VLAN where this host should provide leases, set
`NETBOOT_DHCP_MODE=server` or run `make start DHCP_MODE=server`. Configure the
centralized range, gateway, DNS, and lease-file values in
`config/netboot.env`, and disable the router's DHCP service first. The server
mode warning is intentional but cannot detect a remote competing DHCP server.

## 1. Copy the complete project

Install it at the configured absolute path and preserve ownership, modes, and
symlinks. For example, from the parent directory on the old machine:

```bash
sudo rsync -aH --info=progress2 netboot/ new-host:/srv/netboot/
```

A Git clone alone is not a complete server backup. Downloaded ISOs, extracted
kernels, initramfs images, squashfs files, `tftp/ipxe.efi`, and other prepared
runtime payloads are ignored by Git. Copy them from the old host or run each
package's `prepare.sh` recipe again. The links can be restored independently:

```bash
make links
```

That command repairs missing or incorrect symlinks but refuses to overwrite a
real file or directory at a managed link path.

## 2. Configure the network

Give `eno1` the persistent static address `192.168.1.2/24` using the host's
normal network manager. Confirm it before installing services:

```bash
ip -4 address show dev eno1
```

If the new site differs, edit `config/netboot.env` and adapt the static
configuration before setup. This command locates
the important fixed values:

```bash
rg '192\.168\.1\.2|192\.168\.1\.0|eno1|/srv/netboot' .
```

At minimum, review `config/dnsmasq.conf`, `config/Caddyfile`, iPXE recipes,
the TUI defaults, and the setup helper defaults. The helper environment
variables are useful for checks but do not rewrite those configuration files.

## 3. Check and install

### Arch/CachyOS dependencies

`make packages` installs these official-repository packages with
`pacman -S --needed`: `bash`, `caddy`, `coreutils`, `curl`, `diffutils`,
`dnsmasq`, `findutils`, `gawk`, `gzip`, `grep`, `iproute2`,
`ipxe`, `libarchive`, `procps-ng`, `python`, `sed`, `sudo`, `systemd`, `unzip`, `xorriso`,
and `zstd`. They cover the services, proxy-DHCP/TFTP bootstrap, validation,
TUI, and every included image-preparation recipe. `ipxe` supplies the UEFI
bootstrap at `/usr/share/ipxe/x86_64/ipxe.efi`; the repository's tracked
`undionly.kpxe` supplies the Legacy-BIOS bootstrap because the Arch package
does not ship that binary.

The setup performs no package installation beyond that command. Prepare
recipes also require their respective downloaded ISO or ZIP, checksum, and
signature files; those large runtime artifacts are intentionally not in Git.

Run the read-only host checks first:

```bash
make preflight
```

For a host whose firewall is already managed separately, install packages,
the iPXE bootstrap, links, and services without changing firewall policy:

```bash
make setup
```

To detect UFW or firewalld and interactively add the project rules, run:

```bash
make firewall-rules
```

The script asks separately about HTTP, TFTP, and DHCP/PXE rules. It supports an
already-active UFW or firewalld installation and does not install either
backend. Rules are restricted to source `192.168.1.0/24` where appropriate;
DHCP server traffic also requires UDP 67/68 handling. Remove the rules later
with `make firewall-remove`.

The service step renders configuration into `.runtime/generated/` and starts
Caddy and dnsmasq directly. No `/etc` service files, systemd units, or system
journal configuration are installed. The processes still require elevated
access because PXE/TFTP/HTTP use privileged ports.

## 4. Validate and operate

Check rendered configuration, verified daemon identity, listeners, bootstrap,
and local menu response:

```bash
make validate
```

The Make targets delegate routine work to `scripts/netbootctl`:

```bash
make start
make stop
make reload
make logs
make tui
```

`make logs` follows both journals until Ctrl-C. `make tui` opens the passive
PXE/TFTP/HTTP monitor. You can also run `./scripts/netbootctl` without an
argument for its interactive menu.

Finally, boot a UEFI client on the same LAN and confirm the sequence in the
logs. The supplied bootstrap is UEFI x86_64. Secure Boot is not configured;
leave it disabled on clients unless you separately provide a trusted, signed
boot chain.
