#!/usr/bin/env bash
set -euo pipefail

# Backward-compatible name for the repository-local standalone reload path.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/netbootctl" reload
