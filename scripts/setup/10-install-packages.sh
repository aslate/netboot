#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"
require_project_location

family=$(detect_host_family) || exit 1
case "$family" in
    arch) exec "$SETUP_DIR/10-install-packages-arch.sh" ;;
    fedora) exec "$SETUP_DIR/10-install-packages-fedora.sh" ;;
esac
