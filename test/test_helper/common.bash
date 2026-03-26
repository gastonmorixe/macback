#!/usr/bin/env bash

MACBACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export MACBACK_ROOT
export MACBACK_STATE_DIR="$BATS_TEST_TMPDIR/state"
export MACBACK_OUTPUT_DIR="$BATS_TEST_TMPDIR/output"
export MACBACK_PRIMARY_USER="tester"
export MACBACK_PRIMARY_HOME="$BATS_TEST_TMPDIR/home"
export MACBACK_PLAIN_UI="1"

mkdir -p "$MACBACK_STATE_DIR" "$MACBACK_OUTPUT_DIR" "$MACBACK_PRIMARY_HOME"

source "$MACBACK_ROOT/macback"

assert_success() {
  if [[ "$status" -ne 0 ]]; then
    echo "Expected success, got status=$status" >&2
    echo "${output-}" >&2
    return 1
  fi
}

assert_failure() {
  if [[ "$status" -eq 0 ]]; then
    echo "Expected failure, got status=0" >&2
    echo "${output-}" >&2
    return 1
  fi
}

assert_output_contains() {
  local needle="$1"
  if [[ "${output-}" != *"$needle"* ]]; then
    echo "Expected output to contain: $needle" >&2
    echo "${output-}" >&2
    return 1
  fi
}

assert_file_exists() {
  local path="$1"
  [[ -e "$path" ]] || {
    echo "Expected file to exist: $path" >&2
    return 1
  }
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  [[ -e "$path" ]] || {
    echo "Expected file to exist: $path" >&2
    return 1
  }
  grep -F -- "$needle" "$path" >/dev/null 2>&1 || {
    echo "Expected file to contain: $needle" >&2
    echo "File: $path" >&2
    return 1
  }
}
