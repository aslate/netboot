# S1 handover — Fedora host support

Result: S1 repository work complete. S2 was explicitly selected for preparation; no service work has started.

- T0 centralized shell-only host values in `config/netboot.env`; static dnsmasq, Caddy, iPXE, GRUB, and Python values remain unchanged by user choice.
- T1 mapped the call graph, preparation commands, package providers, payload links, and pre-existing work in `S1-plan.md`. This Fedora 44 container cannot inspect the host's installed `/etc/dnsmasq.conf`, include tree, service state, or SELinux labels. The user confirmed this checkout is mounted on the host at `/srv/netboot`.
- T2 added `make packages` OS dispatch, Fedora package lookup before install, complete preparation dependencies, Fedora iPXE source paths, and bootstrap compare/preserve/force behavior. Fedora package names and iPXE file paths were checked against official Fedora package listings. No package transaction, service activation, or firewall change ran here.
- Validation: 21 Python tests passed (14 previous + 7 isolated platform cases); Bash syntax, ShellCheck on scoped tracked scripts, `git diff --check`, and `make -n packages` passed.
- Existing Super Grub edits, deleted runbook files, and untracked material were preserved. A prior root-level `.netboot-edit-do2kxj9d` temporary file still cannot be removed through this mount; clean it on the host when possible.

Next entry: at T3, inspect the actual installed dnsmasq main config and all active includes, `/etc/caddy/Caddyfile`, existing backup files, unit state, Fedora service users, firewalld zone, and SELinux labels before writing or activating anything. Keep original backups outside included directories and preserve all unrelated operator settings.

Committed S1 and pre-existing work on `codex/fedora-host-support`: `dd605e1`, `e268348`, `cfe7d39`, `a86b6e9`, `67f12b4`.
