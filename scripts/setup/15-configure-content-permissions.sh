#!/usr/bin/env bash
set -euo pipefail

# Create the dedicated content groups and make the configured owner responsible
# for both trees.  Group inheritance keeps files created later service-readable.
# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"
require_project_location

content_owner=${NETBOOT_CONTENT_OWNER:-aslate}
tftp_group=${NETBOOT_TFTP_GROUP:-tftp}
http_group=${NETBOOT_HTTP_GROUP:-httpd}

id "$content_owner" >/dev/null 2>&1 || {
    echo "Configured content owner does not exist: $content_owner" >&2
    exit 1
}

ensure_group() {
    local group=$1
    if ! getent group "$group" >/dev/null; then
        run_as_root groupadd --system "$group"
    fi
    run_as_root usermod --append --groups "$group" "$content_owner"
}

ensure_group "$tftp_group"
ensure_group "$http_group"

set_tree_permissions() {
    local root=$1 group=$2
    run_as_root install -o "$content_owner" -g "$group" -d -m 2775 "$root"
    run_as_root find "$root" -type d -exec chown "$content_owner:$group" {} + -exec chmod g+rX,g+s {} +
    run_as_root find "$root" -type f -exec chown "$content_owner:$group" {} + -exec chmod g+r {} +
}

set_tree_permissions "$PROJECT_ROOT/tftp" "$tftp_group"
set_tree_permissions "$PROJECT_ROOT/http" "$http_group"
echo "Configured $content_owner ownership for TFTP and HTTP content."
