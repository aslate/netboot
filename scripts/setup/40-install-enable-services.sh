#!/usr/bin/env bash
set -euo pipefail

# Standalone mode keeps service configuration, state, and lifecycle in the
# repository.  This compatibility entry point intentionally delegates to the
# repository-local controller and does not install /etc files or systemd units.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "$ROOT/scripts/netbootctl" start
