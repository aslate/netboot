#!/usr/bin/env bash
set -euo pipefail

echo "Standalone Caddy access logging is already enabled in the repository-local log."
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/netbootctl" reload
