#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Checking development dependencies"
command -v bats >/dev/null 2>&1 || {
  echo "ERROR: bats is required." >&2
  echo "Install it with Homebrew: brew install bats-core" >&2
  exit 1
}
command -v shellcheck >/dev/null 2>&1 || {
  echo "ERROR: shellcheck is required." >&2
  echo "Install it with Homebrew: brew install shellcheck" >&2
  exit 1
}

echo "Development environment is ready for $ROOT_DIR"
