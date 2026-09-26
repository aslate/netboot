# Netboot operating model and reference implementations

This document records the implementation that is actually running. It is a
lightweight operational reference, not a package framework specification.

## Architecture

The active handoff is:

```text
PXE client
  -> router DHCP supplies the client lease
  -> dnsmasq proxy-DHCP supplies PXE metadata on eno1
  -> TFTP tftp/ipxe.efi
  -> iPXE HTTP http://192.168.1.2/menu/main.ipxe
  -> selected package boot.ipxe
  -> Caddy HTTP kernel, initramfs, and live/installer payload
  -> target-specific live environment
```

The service-owned configuration is kept in the project and installed by
`scripts/apply-netboot-config.sh`:

```text
config/dnsmasq.conf  -> /etc/dnsmasq.d/netboot.conf
config/Caddyfile     -> /etc/caddy/Caddyfile
```

The current configuration uses `eno1` and `192.168.1.2`. dnsmasq uses proxy
DHCP, TFTP, and PXE metadata; the router remains the authoritative ordinary
DHCP server. Caddy serves `/srv/netboot/http` on TCP port 80. The active
reference flow needs `tftp/ipxe.efi`; the larger GRUB and Alma trees under
`tftp/` are retained experiments, not prerequisites for the working
targets.

### Directory responsibilities

```text
netboot/
├── config/              project-owned server configuration
├── http/                Caddy document root and compatibility links
├── tftp/                dnsmasq TFTP root and retained experiments
├── packages/            boot-target-specific material
├── scripts/             server-wide administration
├── docs/                operational and reference documentation
├── archive/             retained obsolete or historical material
├── .guided-runbook/     tracked execution context from earlier work
├── README.md            project entry point
└── .gitignore           source/runtime boundary rules
```

The runtime also contains ignored downloaded or extracted material such as
`packages/*/vmlinuz`, `initrd.img`, `filesystem.squashfs`, ISO files,
`packages/cachyos/arch/`, the extracted `alma10/` tree, and preserved empty
or experimental serving directories. These are not package framework data;
they are files needed by the current server or retained for investigation.

The working package directories are exposed through tracked HTTP
compatibility links:

```text
http/clonezilla  -> ../packages/clonezilla
http/gparted     -> ../packages/gparted
http/debian-live -> ../packages/debian-live
http/cachyos     -> ../packages/cachyos
http/systemrescue -> ../packages/systemrescue
http/rescuezilla -> ../packages/rescuezilla
http/fedora-workstation -> ../packages/fedora-workstation
http/fedora-sway -> ../packages/fedora-sway
http/fedora-installer -> ../packages/fedora-installer
```

## Lightweight package convention

A package is a directory containing the material specific to one boot target.
The convention currently established by the working packages is:

```text
packages/<name>/
├── package.conf    # NAME and VERSION
├── boot.ipxe       # target-specific iPXE handoff
├── prepare.sh      # target-specific extraction/preparation, executable
└── ...             # source media, checksums, signatures, notes, payloads
```

`README.md` is optional and useful for a package with operational caveats.
Source archives and verification files stay beside the package recipe when
they are retained. Prepared kernels, initramfs files, squashfs files, ISO
files, and extracted trees are runtime artifacts and are ignored according to
the package-specific rules in `.gitignore`.

The package directories are organisational boundaries only. There is no
manifest schema, package manager, generator, plugin system, or requirement
that every package use the same internal extraction layout.

Each working package is currently served by a same-named link below `http/`.
The menu chains to `/clonezilla/boot.ipxe`, `/gparted/boot.ipxe`,
`/debian-live/boot.ipxe`, `/cachyos/boot.ipxe`, `/systemrescue/boot.ipxe`,
`/rescuezilla/boot.ipxe`, `/fedora-workstation/boot.ipxe`, `/fedora-sway/boot.ipxe`, or
`/fedora-installer/boot.ipxe`. The server address is currently written into the
iPXE recipes because that is the established working configuration; do not
replace it with a new variable system merely for aesthetic consistency.

## Boot patterns

### Debian/live-boot family

Clonezilla, GParted Live, and Debian Live use the same broad live-boot shape:

```ipxe
dhcp
set base http://192.168.1.2/<package>
initrd --name initrd.img ${base}/initrd.img
kernel ${base}/vmlinuz initrd=initrd.img boot=live ... fetch=${base}/filesystem.squashfs
imgstat
boot
```

The initramfs brings up the network, fetches `filesystem.squashfs` over HTTP,
and mounts it as the live root. `boot=live` and `fetch=` are the important
handoff parameters. The remaining parameters are package-specific:

- Clonezilla adds its `ocs_live_*` options and live-session defaults.
- GParted adds its username, log-level, and utility-oriented defaults.
- Debian Standard uses the minimal `boot=live components fetch=` recipe and
  intentionally provides a text-oriented Standard environment rather than a
  desktop UI.

The source media differ even within this family. Clonezilla and GParted use
ZIP distributions whose `live/` files are extracted. Debian uses an ISO whose
`live/` files are extracted. The prepared HTTP names are intentionally the
same: `vmlinuz`, `initrd.img`, and `filesystem.squashfs`.

### Ubuntu/casper family

Rescuezilla uses Ubuntu's `casper` live-initramfs rather than Debian
live-boot. Its working package extracts `casper/vmlinuz` and
`casper/initrd.lz`, but serves the complete ISO as the live-media payload.
The iPXE handoff uses:

```text
boot=casper
netboot=url
url=http://192.168.1.2/rescuezilla/rescuezilla-2.6.2-64bit.resolute.iso
ip=dhcp
toram
```

`url=` is the important distinction: casper downloads and mounts the complete
ISO, rather than consuming a direct `filesystem.squashfs` URL through the
Debian/live-boot `fetch=` mechanism. `toram` leaves the live environment
independent of the HTTP server after the ISO has been retrieved. Rescuezilla's
native boot configuration also retains graphical startup and skip-check
options; the package keeps those options local to its recipe.

This is currently a package-specific Ubuntu/casper reference. Do not treat it
as a shared package abstraction until another successful image demonstrates
the same handoff.

### Fedora dracut/LiveOS family

Fedora Workstation uses Fedora's dracut live-initramfs rather than Debian
live-boot, Ubuntu casper, or Archiso. Its ISO stores the boot pair under
`boot/x86_64/loader/linux` and `boot/x86_64/loader/initrd`, with the live root
at `LiveOS/squashfs.img`.

The working package extracts those three files and uses the dracut network
handoff:

```text
root=live:http://192.168.1.2/fedora-workstation/squashfs.img
rd.live.image
ip=dhcp
```

The HTTP URL points directly to Fedora's compressed LiveOS filesystem rather
than to a complete ISO or a Debian-style `filesystem.squashfs` fetched by
`live-boot`. Fedora's native `root=live:CDLABEL=...` media discovery is
replaced with the HTTP URL for network boot. Fedora Sway Live demonstrates the
same handoff, so this is now the project's working Fedora dracut/LiveOS
reference pattern.

Fedora Sway Live is prepared with the same Fedora dracut/LiveOS handoff. Its native ISO
uses the same `boot/x86_64/loader/linux`, `boot/x86_64/loader/initrd`, and
`LiveOS/squashfs.img` paths as Workstation, with a Sway-specific CD label.
The package replaces that physical-media label with an HTTP `root=live:` URL
and keeps `rd.live.image ip=dhcp`. End-to-end client boot validation remains
pending, so the package stays a target-specific implementation until that test
is completed.

### Archiso family

CachyOS uses Archiso and must retain the source tree shape expected by its
initramfs. Its working HTTP paths are:

```text
/cachyos/arch/boot/x86_64/vmlinuz-linux-cachyos
/cachyos/arch/boot/x86_64/initramfs-linux-cachyos.img
/cachyos/arch/x86_64/airootfs.sfs
/cachyos/arch/x86_64/airootfs.sha512
```

The important parameters are:

```text
archisobasedir=arch
archiso_http_srv=http://192.168.1.2/cachyos/
BOOTIF=${net0/mac}
ip=dhcp
checksum=y
```

`archiso_http_srv` must end with `/`; Archiso then appends
`archisobasedir`, architecture, and the live filesystem name. `BOOTIF` makes
the initramfs use the interface that performed PXE when the client has more
than one network interface. `checksum=y` fetches and validates the shipped
`airootfs.sha512`. The ISO did not contain a CMS signature, so the recipe does
not request `cms_verify=y`. Physical-ISO discovery parameters such as
`archisosearchuuid` are not used because the client boots the files over HTTP.

The package keeps the `arch/` subtree rather than flattening it into generic
`vmlinuz`, `initrd.img`, and `filesystem.squashfs` names. That difference is a
boot-family requirement, not a layout failure.

### Fedora Anaconda network installer

The Fedora KDE Installer package uses the official Fedora 44 Everything
netinst ISO as source material, but retrieves the actual installation tree
online. It extracts `images/pxeboot/vmlinuz` and
`images/pxeboot/initrd.img` for HTTP booting, then passes:

```text
inst.repo=https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/os/
inst.ks=http://192.168.1.2/fedora-installer/fedora-kde.ks
ip=dhcp
rd.neednet=1
```

The Kickstart owns the destructive test-machine policy: GPT/UEFI on `sda`,
LVM layout, KDE package selection, SSH key injection, temporary password
expiry, office-suite exclusions, and Avahi service masking. The installer is
now a working Anaconda reference, while AlmaLinux remains a separate parked
and incomplete experiment.

### Anaconda/RHEL family: parked

AlmaLinux is an Anaconda boot-ISO/netinstall experiment, not a working
reference. It needs an installer stage/runtime and a package repository, not a
Debian-style live squashfs fetch. The current experiment uses the extracted
`/alma10/` tree for `inst.stage2`, a remote AlmaLinux repository for `inst.repo`,
and a package-local Kickstart. Its large installer initramfs and GRUB/TFTP
fallbacks are retained for future investigation.

## Source verification and preparation

Verification material is retained in the package, but the preparation scripts
reflect the source project's formats rather than a universal verification
interface:

| Package | Source | Retained verification material | Preparation result |
| --- | --- | --- | --- |
| Clonezilla | ZIP | SHA-256 file and pinned expected hash | `live/` kernel, initramfs, squashfs |
| GParted Live | ZIP | `CHECKSUMS.TXT` and GPG signature | `live/` kernel, initramfs, squashfs |
| Debian Live | ISO | `SHA256SUMS` and detached signature | `live/` kernel, initramfs, squashfs |
| CachyOS | ISO | `.sha256` and ISO `.sig` | retained `arch/` subtree |
| Rescuezilla | ISO | upstream `SHA256SUM` | `casper/` kernel and initrd; complete ISO served for casper URL boot |
| Fedora Workstation | ISO | signed upstream checksum file and pinned SHA-256 | `boot/x86_64/loader` kernel/initrd and `LiveOS/squashfs.img` |
| Fedora Sway Live | ISO | signed upstream checksum file and pinned SHA-256 | `boot/x86_64/loader` kernel/initrd and `LiveOS/squashfs.img` |
| Fedora KDE Installer | ISO | signed upstream checksum file and pinned SHA-256 | `images/pxeboot` kernel/initrd; online Everything tree and HTTP Kickstart |

The scripts currently perform a pinned SHA-256 check before extraction. The
retained upstream signatures are evidence for acquisition and manual
verification; they are not a new common package API. Do not broaden this into
a packaging framework during an image addition.

All working preparation scripts use a package-local or project-local temporary
stage and clean it after extraction. CachyOS additionally makes the extracted
ISO files writable before replacing its prepared tree because ISO extraction
preserves read-only modes.

## Reference implementations

| Package | Status | Boot family | Source format | Live-root/network mechanism | Useful as reference for |
| --- | --- | --- | --- | --- | --- |
| Clonezilla | Working | Debian/live-boot with Clonezilla options | amd64 ZIP | `boot=live`; `fetch=` HTTP squashfs | live utility images with custom live-session parameters |
| GParted Live | Working | Debian/live-boot | amd64 ZIP | `boot=live`; `fetch=` HTTP squashfs | small live utilities distributed as ZIP |
| Debian Live | Working | Debian/live-boot | amd64 Standard ISO | `boot=live`; `fetch=` HTTP squashfs | Debian live images and minimal live-boot recipes |
| CachyOS | Working | Archiso | Desktop ISO | `archiso_http_srv`; `archisobasedir=arch`; checksum fetch | Archiso-based desktop/live images |
| Rescuezilla | Working | Ubuntu/casper | amd64 Resolute ISO | `netboot=url`; `url=` HTTP complete ISO | Ubuntu/casper live images |
| Fedora Workstation | Working | Fedora dracut/LiveOS | amd64 Workstation ISO | `root=live:` HTTP `LiveOS/squashfs.img` | Fedora and compatible dracut live images |
| Fedora Sway Live | Prepared; client test pending | Fedora dracut/LiveOS | amd64 Sway Spin ISO | `root=live:` HTTP `LiveOS/squashfs.img` | Fedora dracut/LiveOS desktop spins |
| Fedora KDE Installer | Working | Anaconda/Fedora installer | amd64 Everything netinst ISO | `inst.repo` online tree plus `inst.ks` HTTP Kickstart | Fedora network installers and Kickstart-driven Anaconda installs |
| AlmaLinux | Parked | Anaconda/RHEL installer | boot ISO | incomplete stage2/repository/client handoff | not yet a reference |

When adding image X, choose the row by boot technology and media shape rather
than by operating-system name alone.

## Adding another image

Use this practical sequence:

1. Inspect the upstream image and its native boot configuration.
2. Identify its boot technology and whether it is a live image, installer, or
   utility image.
3. Compare it with the closest working package above.
4. Create `packages/<name>/` with only the metadata and recipes that image
   needs.
5. Verify the source media before extraction and retain useful upstream
   checksum/signature material.
6. Implement the package-specific preparation and `boot.ipxe` behaviour.
7. Expose the required files through the existing `http/<name>` compatibility
   link and Caddy document root.
8. Add a menu item and chain target in `http/menu/main.ipxe`.
9. Validate the exact HTTP and TFTP resources before booting a client.
10. Test each handoff boundary separately: PXE, iPXE, recipe, kernel/initramfs,
    network, live-root or installer payload, and environment startup.
11. Regression-test at least one existing image, ideally the closest reference
    and one different boot family.

Existing packages are reference implementations, not templates to copy
blindly. Preserve working family-specific parameters and keep unusual logic
inside the package that requires it.

## AlmaLinux parked state

The maintained Alma material is under `packages/almalinux/`:

- `package.conf`, `CHECKSUM`, and the boot ISO identify the source media.
- `alma10-server-gui.ks` is the package-specific Kickstart.
- `prepare.sh` retains the existing extraction, GRUB/TFTP, and diagnostic
  workflow; it is not part of the standard working-package preparation convention.
- `boot.ipxe` and `test-handoff.sh` are diagnostic paths.

The extracted source tree remains under `alma10/` and is exposed as
`/alma10/`. The TFTP tree under `tftp/alma10/`, `http/alma10`,
`http/almalinux`, `http/kickstarts`, and the empty `http/live` placeholders are
deliberately retained. Server-side HTTP delivery and repository/stage2 wiring
were useful findings; the target client has not established a successful
kernel/initramfs-to-installer handoff. Do not treat Alma as a reference or
remove these artifacts until a later Alma investigation resolves their
ownership and usefulness.

## Validation checklist

Run configuration checks before changing services:

```bash
sudo dnsmasq --test --conf-file=/etc/dnsmasq.d/netboot.conf
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl is-active dnsmasq caddy
```

Check for broken links and stale active references:

```bash
find -L http tftp -type l -print
rg -n 'clonezilla/|gparted/|debian-live/|cachyos/|systemrescue/|rescuezilla/|fedora-workstation/|fedora-sway/|fedora-installer/|alma10/|kickstarts/' \
  config http packages scripts README.md docs
```

Before client testing, verify the menu, each package recipe, and each package's
kernel, initramfs, and live root with HTTP `HEAD` or range requests. Confirm
that `tftp/ipxe.efi` is readable by the TFTP service. During a client test,
watch the dnsmasq and Caddy journals and identify the first missing handoff
request instead of changing the package layout.

## Future `add-netboot-image` skill candidate

The repeated, mechanically similar work is bounded and identifiable:

1. inspect and classify source media and native boot configuration;
2. create package metadata and a preparation script;
3. verify/extract the required boot files;
4. expose them through an HTTP compatibility link;
5. write a package-specific iPXE recipe;
6. add and validate one menu entry;
7. run URL, service, and regression checks.

A future skill could guide those checks and create a small package skeleton,
but it must leave the boot-family decision, kernel parameters, verification
method, and unusual preparation logic to the image-specific implementation.
That skill is intentionally not implemented in this reconciliation pass.
