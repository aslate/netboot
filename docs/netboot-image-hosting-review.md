# Netboot Image Hosting Review

> Historical troubleshooting record: this document primarily records the
> AlmaLinux investigation. Its paths and intermediate workarounds describe
> experiments, not the authoritative current layout. Use `README.md` and
> `docs/netboot-reference.md` for the current server model.

## Purpose

This review records the problems encountered while building the AlmaLinux 10 PXE installation path on the CachyOS netboot server. It is intended as a troubleshooting reference for hosting other Linux installers and recovery images.

## Reference architecture

The working service layout is:

```text
authoritative router DHCP
        |
        +-- client lease

CachyOS 192.168.1.2/24 on eno1
        |
        +-- dnsmasq proxy-DHCP + TFTP
        +-- Caddy HTTP on TCP/80
```

The router remains the authoritative DHCP server. `dnsmasq` supplies PXE boot information through proxy-DHCP. The intended transport split is:

```text
TFTP: small bootstrap only
HTTP: scripts, kernels, initramfs, installer trees, and images
```

## Issue review

### 1. Two DHCP models were mixed

**Symptoms:** E16/E18 errors, no offer, or the client receiving a lease but no usable boot file.

**Diagnosis:** The LAN already had a router at `192.168.1.1` providing leases. The netboot host initially used ordinary DHCP assumptions and later used an unsuitable restricted range. Packet captures showed two DHCP responders: the router supplied `192.168.1.175`, while dnsmasq supplied PXE information.

**Resolution:** Use dnsmasq proxy-DHCP on the existing `/24` network:

```ini
dhcp-range=192.168.1.0,proxy
```

Do not run a second ordinary DHCP pool on the same LAN. For an isolated VLAN, use a normal dnsmasq DHCP range instead.

**General lesson:** First identify the authoritative DHCP server and choose either ordinary DHCP or proxy-DHCP. Do not infer this from the server's own address.

### 2. Incorrect subnet assumptions caused no-offer failures

**Symptoms:** The client displayed `192.168.1.175`, while the server configuration was using a `/30` concept or a different subnet.

**Diagnosis:** The packet capture showed a valid `/24` lease from the router. The server and client were on `192.168.1.0/24`, not an isolated `192.168.1.0/30` network.

**Resolution:** Use `192.168.1.2/24`, proxy-DHCP, and firewall rules appropriate to the actual LAN. A `/30` restriction would exclude normal client addresses such as `.175`.

**General lesson:** Treat the client packet capture and router lease as authoritative evidence. Validate interface address, route, netmask, DHCP range, and firewall source range together.

### 3. dnsmasq configuration syntax was initially invalid

**Symptom:** `dnsmasq: bad dhcp-option at line 9`.

**Diagnosis:** A malformed `dhcp-option` line was being interpreted as a DHCP option definition. dnsmasq will not start with a syntactically invalid file.

**Resolution:** Validate the exact file before restart:

```bash
sudo dnsmasq --test --conf-file=/etc/dnsmasq.d/netboot.conf
```

**General lesson:** Keep the service configuration small and run a syntax check before every restart. Do not use ordinary `dhcp-option` syntax for PXE boot-file selection; use `dhcp-boot`, `pxe-service`, and architecture tags.

### 4. Project/runbook artifacts were not present at the assumed path

**Symptom:** `install: cannot stat '/tmp/netboot-runbook/...': No such file or directory`.

**Diagnosis:** The command assumed temporary source artifacts that had not been created in the current session.

**Resolution:** Keep source and runbook artifacts in the project, under `.guided-runbook/`, and make scripts validate required inputs before mutation.

**General lesson:** Never make installation depend on an unverified temporary path. Check files explicitly and fail before changing services.

### 5. Git state was damaged by an interrupted or incomplete repository setup

**Symptoms:** `fatal: not a git repository`, followed by `fatal: .git/index: index file smaller than expected`.

**Diagnosis:** `.git` existed but the index was incomplete/corrupt.

**Resolution:** Preserve working files, avoid destructive resets, and repair only the repository metadata after inspecting the worktree. Generated payloads, ISOs, logs, and leases were kept out of commits.

**General lesson:** Separate source artifacts from generated boot content. Use an explicit allow-list for commits rather than `git add .` in a serving tree.

### 6. A boot ISO is not an installation tree

**Symptoms:** The boot ISO lacked a complete local `.treeinfo`/`BaseOS` tree, and a guessed repository URL returned 404.

**Diagnosis:** The AlmaLinux boot ISO is a network installer. It contains boot files and `images/install.img`, but not the complete package repositories. The installer needs a valid remote `inst.repo` or a separately downloaded/extracted installation tree.

**Resolution:** Serve the extracted boot-ISO content locally for `inst.stage2`, while using the official remote AlmaLinux BaseOS kickstart repository for `inst.repo`.

**General lesson:** Classify image media before designing the boot path:

| Media type | Provides installer runtime | Provides packages | Typical use |
|---|---:|---:|---|
| Boot/netinstall ISO | Yes | No or partial | HTTP/TFTP boot plus remote repository |
| DVD/full installer tree | Yes | Yes | Fully local HTTP installation |
| Live ISO | Live root filesystem | Usually self-contained | Live boot, not normal Anaconda install |

Do not use `inst.repo` against a directory that lacks valid repository metadata.

### 7. Checksum handling had to preserve an existing ISO

**Symptom:** The checksum parser could not find an entry, and there was a requirement not to redownload the ISO.

**Diagnosis:** AlmaLinux's `CHECKSUM` file uses entries such as:

```text
SHA256 (AlmaLinux-10-latest-x86_64-boot.iso) = <hash>
```

The script initially assumed a different format.

**Resolution:** Parse the named `SHA256 (...) = ...` entry and reuse non-empty local ISO/checksum files. Verify the local ISO before mounting or extracting it.

**General lesson:** A download script must distinguish “missing” from “present but invalid”. Never overwrite a supplied image merely because a remote filename is available.

### 8. Direct iPXE handoff created a loop

**Symptom:** iPXE was repeatedly offered `ipxe.efi` after it had already started.

**Diagnosis:** The DHCP response did not distinguish the firmware's initial PXE request from iPXE's second DHCP request.

**Resolution:** Match iPXE's DHCP option 175 and change the second-stage boot file to an HTTP script:

```ini
dhcp-match=set:ipxe,175
dhcp-boot=tag:ipxe,http://192.168.1.2/menu/almalinux.ipxe,,0.0.0.1
```

Firmware clients receive `ipxe.efi`; iPXE clients receive the HTTP script.

**General lesson:** Every chainloaded network bootloader needs a loop-break condition. Option 175 is the documented iPXE detection mechanism.

### 9. GRUB rescue occurred before module/config loading

**Symptoms:** The client fetched GRUB's EFI image and entered `grub rescue`; the server saw no requests for `normal.mod` or `grub.cfg`.

**Diagnosis:** The firmware delivered `core.efi`, but that GRUB image did not reliably reconstruct its network context after the UEFI handoff on this client.

**Workaround attempted:** Generate a documented GRUB network tree with:

```bash
grub-mknetdir --net-directory=/srv/netboot/tftp \
  --subdir=boot/grub -d /usr/lib/grub/x86_64-efi
```

Then embed DHCP, the TFTP server, and the GRUB prefix into a custom EFI core image before loading `normal.mod`.

**Result:** GRUB became usable and fetched its configuration. This was a valid fallback for GRUB-capable clients, but it was not retained as the primary AlmaLinux handoff because of the next issue.

**General lesson:** A GRUB rescue prompt with no module request usually indicates a prefix/network-context problem, not a missing menu file. Confirm the server-side request sequence before changing menu syntax.

### 10. The large initramfs timed out over TFTP

**Symptom:** `dnsmasq-tftp: timeout sending ... initrd.img`.

**Diagnosis:** The AlmaLinux initramfs is approximately 226 MB. The client could receive the kernel but could not complete the large TFTP transfer reliably.

**Workaround attempted:** Move kernel/initramfs delivery from TFTP to HTTP. Caddy returned `200 OK` for both files.

**General lesson:** Keep TFTP limited to a small bootstrap. Use HTTP for large kernels, initramfs files, installer trees, and live images. A successful local `curl` test proves server availability, but not that the client bootloader can consume the file.

### 11. GRUB's EFI HTTP implementation stalled on the initramfs

**Symptoms:** GRUB fetched the kernel, opened HTTP connections for the initramfs, and then made almost no progress. TCP statistics showed retransmissions and a tiny receive window. No installer-stage HTTP requests followed.

**Diagnosis:** Caddy was healthy and serving the file; the failure was the client's GRUB EFI HTTP stack.

**Resolution:** Replace GRUB's payload handoff with iPXE HTTP loading.

**General lesson:** Test each bootloader's HTTP implementation independently. “HTTP 200 from the server” does not prove that GRUB, iPXE, or a firmware HTTP stack can transfer and retain a large initramfs.

### 12. iPXE downloaded both images but stopped at the UEFI Linux handoff

**Symptoms:** Caddy logged completed iPXE GETs for both `vmlinuz` and `initrd.img`, then no requests for `install.img` or Kickstart. The client showed the kernel command line and appeared stuck.

**Diagnosis:** Network delivery was complete. The remaining failure was between iPXE's `boot` command and early Linux/initramfs execution. On UEFI clients, explicitly naming the initrd is necessary; loading the initrd before the kernel is also a useful compatibility workaround for firmware with restrictive memory mapping.

**Workaround attempted:**

```ipxe
initrd --name initrd.img http://server/alma10/images/pxeboot/initrd.img
kernel http://server/alma10/images/pxeboot/vmlinuz \
  ip=dhcp initrd=initrd.img ...
imgstat
boot
```

**Current status:** The script has been updated and committed, but this handoff still needs confirmation on the target client.

**General lesson:** For UEFI iPXE Linux boots:

1. Download the initrd first.
2. Give it a stable name.
3. Pass the exact same name as `initrd=`.
4. Use `imgstat` before `boot`.
5. Add temporary `console=tty0`, `inst.text`, or `rd.debug` arguments when graphics or early console output is ambiguous.

## Caddy logging issue

**Symptoms:** Caddy reload failed while adding file access logging:

```text
permission denied opening /var/log/caddy/access.log
```

**Diagnosis:** The packaged systemd service has filesystem hardening and the validation/reload path did not reliably permit the selected file target.

**Resolution:** Send access logs to stdout. systemd captures them in the Caddy journal:

```caddy
log {
    output stdout
    format json
}
```

Use:

```bash
sudo journalctl -f -u dnsmasq.service -u caddy.service -o short-iso
```

**General lesson:** Prefer journald for small netboot services unless a dedicated log directory has been verified writable by both the service user and its systemd sandbox.

## Reusable validation sequence for another Linux image

Before booting a client, validate in this order:

1. Classify the media: boot/netinstall, DVD tree, live image, or utility image.
2. Verify the image checksum and record the source URL.
3. Identify the authoritative DHCP server and choose proxy-DHCP or ordinary DHCP.
4. Validate dnsmasq syntax without restarting it.
5. Confirm the bootstrap file is visible by TFTP.
6. Confirm the HTTP script, kernel, initramfs, installer runtime, and Kickstart/preseed files return `200 OK`.
7. Confirm the DHCP architecture match selects the intended UEFI or BIOS bootstrap.
8. Confirm the second DHCP request is recognized as iPXE, if chainloading.
9. Watch the client-specific request sequence, not just service status.
10. Only after the kernel/initramfs handoff succeeds, diagnose installer repository or automation issues.

## Evidence patterns

| Server evidence | Likely boundary |
|---|---|
| No DHCPDISCOVER | Network, VLAN, firmware, cable, or client boot mode |
| Lease from router, no PXE boot file | Proxy-DHCP match or competing PXE server |
| Bootstrap TFTP only | Bootloader execution or next DHCP request |
| GRUB rescue, no module requests | GRUB prefix/network context |
| Kernel TFTP succeeds, initrd TFTP times out | Large-file TFTP limitation |
| Caddy gets GRUB/iPXE GETs, no installer GETs | Kernel/initramfs handoff |
| Installer GETs `install.img` but not repository | `inst.stage2`/tree layout |
| Installer reads repository but ignores automation | Kickstart/preseed URL or validator issue |

## Security and operational notes

- Do not expose DHCP or TFTP beyond the intended netboot VLAN.
- Keep the installation tree and large images on HTTP; keep TFTP minimal.
- Treat `inst.ks` and other automation files as sensitive configuration.
- The current test Kickstart uses the temporary plaintext password `changeme`; replace it before any real deployment.
- The current disk policy deliberately selects the first non-removable writable disk and erases it. Do not reuse it unchanged on heterogeneous hardware.
- Keep generated ISO contents, leases, packet captures, HTTP logs, and TFTP payloads out of Git unless there is a specific reason to version them.

## Relevant references

- [iPXE chainloading](https://ipxe.org/howto/chainloading)
- [iPXE proxy-DHCP](https://ipxe.org/appnote/proxydhcp)
- [iPXE kernel and initrd commands](https://ipxe.org/cmd/kernel)
- [GNU GRUB network boot](https://www.gnu.org/software/grub/manual/grub/html_node/Network.html)
- [RHEL 10 PXE installation source](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/automatically_installing_rhel/preparing-a-pxe-installation-source)
