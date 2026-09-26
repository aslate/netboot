# S2 — Recoverable service setup and Fedora host policy

Entry: S1 is complete on `codex/fedora-host-support`. T3 and T4 are queued; no service configuration or host policy has been changed by this session.

Before T3 writes anything, inspect the Fedora 43 host's actual `/etc/dnsmasq.conf`, every active `conf-dir`/`conf-file` and systemd unit argument, `/etc/caddy/Caddyfile`, existing project backup files, file existence/mode/owner, and caddy/dnsmasq active and enabled state. The checkout's `config/dnsmasq.conf` and `config/Caddyfile` are source files, while `/etc` is not visible inside the Fedora 44 container. Record the effective include path and duplicate-fragment risk before selecting the one project include strategy.

T3: share one install function between setup and reload. Back up originals and per-run state under `/var/backups/netboot`, including absent-file cases; keep backup files outside dnsmasq includes. Stage candidates, then validate the installed effective dnsmasq configuration and installed Caddy configuration before enabling or restarting. On stage/validation failure, restore exact files and leave running services untouched. Report partial service state and a restore/restart path if activation fails. Verify user/group `dnsmasq:dnsmasq` exists before TFTP ownership changes.

T4: add `make selinux` and reconcile persistent labels on actual served inodes and traversal paths after install, before activation on Fedora. Inspect existing local fcontext overrides, handle disabled SELinux, and verify labels/readability. Keep firewall changes opt-in and tied to the interface zone; normal source remains `192.168.1.0/24`, with a separate DHCP-only `0.0.0.0/32` rule. Make add/remove symmetric and idempotent.

Validation: isolated fake-root and command-mocked tests for include ambiguity, duplicate/legacy fragments, exact rollback including originally absent files, disabled/enforcing SELinux, repeat convergence, firewall rule matrix, and activation failure reporting. Run existing Python tests plus syntax/ShellCheck on changed scripts. Do not run host activation from this container. Leave S3 inactive until S2 exit and explicit selection.

Host input still needed: the installed `/etc` configuration and service/SELinux/firewalld status from the Fedora 43 host. No package installation, `make setup`, `make services`, `make firewall`, or client boot should run to obtain this read-only evidence.
