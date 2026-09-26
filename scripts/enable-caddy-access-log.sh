#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/setup/_common.sh"
ROOT=$PROJECT_ROOT
CADDYFILE="$ROOT/config/Caddyfile"
INSTALLED_CADDYFILE=/etc/caddy/Caddyfile

if [[ ${EUID} -ne 0 ]]; then
    exec sudo "$BASH" "$0" --root
fi

test -f "$CADDYFILE"

if grep -qF 'output file /var/log/caddy/access.log' "$CADDYFILE"; then
    sed -i 's#output file /var/log/caddy/access.log#output stdout#' "$CADDYFILE"
elif grep -qF 'output file /var/lib/caddy/access.log' "$CADDYFILE"; then
    sed -i 's#output file /var/lib/caddy/access.log#output stdout#' "$CADDYFILE"
elif ! grep -qE '^[[:space:]]*log[[:space:]]*\{' "$CADDYFILE"; then
    cp -a "$CADDYFILE" "$CADDYFILE.before-access-log"
    awk '
        /^}/ && !inserted {
            print "    log {"
            print "        output stdout"
            print "        format json"
            print "    }"
            inserted = 1
        }
        { print }
    ' "$CADDYFILE" > "$CADDYFILE.new"
    install -o root -g root -m 0644 "$CADDYFILE.new" "$CADDYFILE"
    rm -f "$CADDYFILE.new"
fi

install -m 0644 "$CADDYFILE" "$INSTALLED_CADDYFILE"
caddy validate --config "$INSTALLED_CADDYFILE"
systemctl reload caddy
systemctl is-active caddy
echo "Caddy access log: journalctl -u caddy"
