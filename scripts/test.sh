#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v bats >/dev/null 2>&1; then
  echo "ERROR: bats is required. Run scripts/bootstrap-dev.sh first." >&2
  exit 1
fi

cd "$ROOT_DIR"
bats test/unit
bats test/integration
