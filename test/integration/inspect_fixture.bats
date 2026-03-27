#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
  CLI="$MACBACK_ROOT/macback"
  FIXTURE="$BATS_TEST_TMPDIR/fixture-run"
  mkdir -p "$FIXTURE/meta" "$FIXTURE/components/brew"
  printf '%s\n' 'tap "homebrew/core"' > "$FIXTURE/components/brew/Brewfile"
  write_run_env "$FIXTURE/meta/run.env" \
    SPEC_VERSION 1 \
    TOOL_VERSION 0.1.0 \
    CREATED_AT 2026-03-25T00:00:00Z \
    STARTED_AT 2026-03-25T00:00:00Z \
    FINISHED_AT 2026-03-25T00:10:00Z \
    STATUS completed \
    DESTINATION_BASE /Volumes/Test \
    RUN_DIR "$FIXTURE" \
    SOURCE_USER tester \
    SOURCE_HOME /Users/tester
  write_run_json "$FIXTURE/meta/run.json" 2026-03-25T00:00:00Z 2026-03-25T00:00:00Z 2026-03-25T00:10:00Z completed /Volumes/Test "$FIXTURE" tester /Users/tester
  printf '%s\n' '/Users/tester/.ssh/**' > "$FIXTURE/meta/include-paths.txt"
  printf '%s\n' '**/node_modules/**' > "$FIXTURE/meta/exclude-patterns.txt"
  write_manifest_json "$FIXTURE/meta/manifest.json" "$FIXTURE" false true false false false remap_to_target_home preserve_system_remap_user
  write_integrity_checksums "$FIXTURE/meta/integrity" "$FIXTURE/meta/run.json" "$FIXTURE/meta/manifest.json"
}

@test "macback inspect accepts explicit manifest path" {
  run bash "$CLI" inspect "$FIXTURE/meta/manifest.json"
  assert_success
  assert_output_contains "Integrity"
  assert_output_contains "manifest checksums OK"
}

@test "macback inspect accepts run dir path" {
  run bash "$CLI" inspect "$FIXTURE"
  assert_success
  assert_output_contains "Backup inspection"
  assert_output_contains "present"
}

@test "macback inspect handles incomplete backup without manifest" {
  local incomplete="$BATS_TEST_TMPDIR/incomplete-run"
  mkdir -p "$incomplete/meta" "$incomplete/components/files/rootfs"
  write_run_env "$incomplete/meta/run.env" \
    SPEC_VERSION 1 TOOL_VERSION 0.1.0 \
    CREATED_AT 2026-03-25T00:00:00Z STARTED_AT 2026-03-25T00:00:00Z \
    STATUS running DESTINATION_BASE /Volumes/Test RUN_DIR "$incomplete" \
    SOURCE_USER tester SOURCE_HOME /Users/tester
  write_run_json "$incomplete/meta/run.json" 2026-03-25T00:00:00Z 2026-03-25T00:00:00Z "" running /Volumes/Test "$incomplete" tester /Users/tester
  printf '%s\n' '/Users/tester/.ssh/**' > "$incomplete/meta/include-paths.txt"
  printf '%s\n' '**/node_modules/**' > "$incomplete/meta/exclude-patterns.txt"

  run bash "$CLI" inspect "$incomplete"
  assert_success
  assert_output_contains "MISSING"
  assert_output_contains "Backup inspection"
}

@test "macback inspect marks stale running backup as interrupted" {
  local interrupted="$BATS_TEST_TMPDIR/interrupted-run"
  mkdir -p "$interrupted/meta" "$interrupted/components/files/rootfs"
  write_run_env "$interrupted/meta/run.env" \
    SPEC_VERSION 1 TOOL_VERSION 0.1.0 \
    CREATED_AT 2026-03-25T00:00:00Z STARTED_AT 2026-03-25T00:00:00Z \
    STATUS running DESTINATION_BASE /Volumes/Test RUN_DIR "$interrupted" \
    SOURCE_USER tester SOURCE_HOME /Users/tester
  write_run_json "$interrupted/meta/run.json" 2026-03-25T00:00:00Z 2026-03-25T00:00:00Z "" running /Volumes/Test "$interrupted" tester /Users/tester
  printf '999999\n' > "$interrupted/meta/active.pid"

  run bash "$CLI" inspect "$interrupted"
  assert_success
  assert_output_contains "Status"
  assert_output_contains "interrupted"
  assert_output_contains "backup interrupted before finalization"
}
