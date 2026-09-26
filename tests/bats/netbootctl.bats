#!/usr/bin/env bats

setup() {
  ROOT="$(cd -- "$BATS_TEST_DIRNAME/../.." && pwd)"
  CLI="$ROOT/scripts/netbootctl"
}

@test "netbootctl exposes standalone commands" {
  run "$CLI" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Start Caddy and dnsmasq as standalone daemons"* ]]
}

@test "active standalone control has no systemd or journal dependency" {
  run rg -n 'systemctl|journalctl|/etc/(dnsmasq|caddy)' \
    "$ROOT/scripts/netbootctl" "$ROOT/scripts/setup/40-install-enable-services.sh" "$ROOT/scripts/setup/90-validate-host.sh"
  [ "$status" -eq 1 ]
}
