# S1 — Platform support

Entry: preserve all user work. This session is selected for future execution; queue maintenance leaves every task queued.

1. Finish T1 by mapping setup/reload, preparation dependencies, installed config and dnsmasq includes on the target host when available. Record the exact working-tree baseline and verify current tests.
2. Complete T2 by adding supported OS dispatch to `make packages`, retaining the Arch dependency list, resolving Fedora 43 providers before any package transaction, and selecting Fedora's packaged iPXE paths. Keep project-root BIOS image precedence and compare existing destinations before copying.
3. Verify both platform paths, unsupported-host no-mutation, bootstrap idempotence, and force behavior with isolated tests. Re-run relevant Python and shell syntax checks.

Exit: S1 changes are reviewable, the repository remains functional, tests pass, and a handover records decisions for S2. S2 remains inactive until explicitly selected.

## Readiness checked 2026-09-24

The checkout is available and existing Python baseline is 14 passing tests. Fedora 44 container has bash, git, Python, make, shellcheck, and dnf; it lacks dnsmasq, Caddy, bsdtar, SELinux, and firewalld commands. `/srv/netboot` and installed service configuration are absent. S1 repository mapping and isolated tests can start here; Package providers are checked against Fedora 43 package listings. The effective installed dnsmasq include still requires target-host evidence before S2 installation.

Preserve the currently modified menu and link helper, deleted runbook files, and other untracked material. The repo mount is owned by `dev`; commands run as root under the restricted wrapper currently fail before launch, while the `dev` account can write the checkout.

Useful read-only host evidence for T1: `/etc/os-release`; `/etc/dnsmasq.conf` and any referenced include files/directories (or a clear absent report); `/etc/caddy/Caddyfile` if present; `systemctl is-enabled` and `is-active` for dnsmasq/Caddy; `ip -4 address show dev eno1`; and `findmnt -T /srv/netboot` plus a symlink listing of served paths. Redact secrets before sharing. Do not run package installation, setup, firewall, or service activation for this snapshot.

## Scope update 2026-09-24

User clarified that this checkout is mounted on the host at `/srv/netboot`. The project config files are the intended source files. T0 centralized values for native shell setup/preparation in `config/netboot.env`; dnsmasq, Caddy, iPXE, GRUB, and Python remain static by explicit user choice. T1 resumes with the effective installed dnsmasq include and Fedora package-provider map.

## T1 compatibility map and baseline

- `make packages` calls the new platform dispatcher; `make setup` orders packages, bootstrap, links, services, validation. `netbootctl reload` calls `scripts/apply-netboot-config.sh`. The source config is `config/dnsmasq.conf` and `config/Caddyfile`; the current installer writes `/etc/dnsmasq.d/netboot.conf` and `/etc/caddy/Caddyfile`. The currently installed `/etc` files and effective dnsmasq include are unavailable inside this Fedora 44 container, even though the checkout is mounted on the host at `/srv/netboot`; S2 must inspect those on the host before install.
- HTTP `/srv/netboot/http` contains symlinks into `packages/` and `alma10/`. The Fedora installer symlink targets `packages/fedora-installer/`; its ISO, checksum, kernel, and initramfs are present. The iPXE destination files and project-root BIOS candidate are present. Existing Super Grub menu/link edits, deleted runbook files, and other untracked content remain user work.
- Preparation uses `bsdtar`, `unzip`, `curl`, `xorriso`, `zstd`, `gzip`, and checksum/core shell tools. Fedora 43 package providers include `bsdtar`, `unzip`, `xorriso`, `zstd`, `ipxe-bootimgs-x86`, `caddy`, `dnsmasq`, `firewalld`, `iproute`, `policycoreutils`, `policycoreutils-python-utils`, and `libselinux-utils`. Fedora iPXE binaries are `/usr/share/ipxe/ipxe-x86_64.efi` and `/usr/share/ipxe/undionly.kpxe`. Primary package sources: https://packages.fedoraproject.org/pkgs/ipxe/ipxe-bootimgs-x86/fedora-43.html , https://packages.fedoraproject.org/pkgs/libarchive/bsdtar/ , https://packages.fedoraproject.org/pkgs/libisoburn/xorriso/ , https://packages.fedoraproject.org/pkgs/policycoreutils/policycoreutils-python-utils/ .
- Baseline before S1 package changes: 14 existing Python tests passed; shell syntax and ShellCheck passed for the config-env edit. Host service/boot evidence remains unavailable in the container.
