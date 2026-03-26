#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "manifest helpers write and validate backup metadata" {
  local run="$BATS_TEST_TMPDIR/run"
  mkdir -p "$run/meta" "$run/components/files/rootfs" "$run/components/brew" "$run/components/keychain" "$run/components/system" "$run/components/launchd"
  printf '%s\n' 'tap "homebrew/core"' > "$run/components/brew/Brewfile"

  run write_run_env "$run/meta/run.env" \
    SPEC_VERSION 1 \
    TOOL_VERSION 0.1.0 \
    CREATED_AT 2026-03-25T00:00:00Z \
    STARTED_AT 2026-03-25T00:00:00Z \
    STATUS running \
    DESTINATION_BASE /Volumes/Test \
    RUN_DIR "$run" \
    SOURCE_USER tester \
    SOURCE_HOME /Users/tester
  assert_success

  run write_run_json "$run/meta/run.json" 2026-03-25T00:00:00Z 2026-03-25T00:00:00Z "" running /Volumes/Test "$run" tester /Users/tester
  assert_success

  printf '%s\n' '/Users/tester/.ssh/**' > "$run/meta/include-paths.txt"
  printf '%s\n' '**/node_modules/**' > "$run/meta/exclude-patterns.txt"

  run write_manifest_json "$run/meta/manifest.json" "$run" true true true true true remap_to_target_home preserve_system_remap_user
  assert_success

  run validate_backup_manifest "$run/meta/manifest.json"
  assert_success

  run write_integrity_checksums "$run/meta/integrity" "$run/meta/run.json" "$run/meta/manifest.json"
  assert_success

  run verify_manifest_checksums "$run/meta/manifest.json"
  assert_success
}

@test "validate_backup_manifest rejects malformed manifest" {
  local run="$BATS_TEST_TMPDIR/bad-run"
  mkdir -p "$run/meta"
  printf '%s\n' 'SOURCE_USER=tester' 'SOURCE_HOME=/Users/tester' > "$run/meta/run.env"
  printf '%s\n' '{"spec_version":"1"}' > "$run/meta/run.json"
  printf '%s\n' '/Users/tester/.ssh/**' > "$run/meta/include-paths.txt"
  printf '%s\n' '**/node_modules/**' > "$run/meta/exclude-patterns.txt"
  printf '%s\n' '{not-json' > "$run/meta/manifest.json"

  run validate_backup_manifest "$run/meta/manifest.json"
  assert_failure
}
