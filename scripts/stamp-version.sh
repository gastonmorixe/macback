#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT_DIR/lib/common.sh"

version="${1:-}"
if [[ -z "$version" ]]; then
  version="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null)" || {
    echo "No version argument and no git tag found." >&2
    echo "Usage: stamp-version.sh [VERSION]" >&2
    echo "  e.g. stamp-version.sh 0.2.0" >&2
    echo "  or tag first: git tag v0.2.0" >&2
    exit 1
  }
fi

# Strip leading 'v' if present
version="${version#v}"

current="$(sed -n 's/.*MACBACK_TOOL_VERSION="\([^"]*\)".*/\1/p' "$TARGET")"
if [[ "$current" == "$version" ]]; then
  echo "Version already $version"
  exit 0
fi

sed -i '' "s/MACBACK_TOOL_VERSION=\".*\"/MACBACK_TOOL_VERSION=\"$version\"/" "$TARGET"
echo "Stamped $current -> $version in lib/common.sh"
