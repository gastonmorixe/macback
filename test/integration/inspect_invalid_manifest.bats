#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
  CLI="$MACBACK_ROOT/macback"
  FIXTURE="$BATS_TEST_TMPDIR/bad-fixture"
  mkdir -p "$FIXTURE/meta"
}

@test "inspect shows partial info when run.env is missing" {
  printf '%s\n' '{"spec_version":"1","components":{"files":true}}' > "$FIXTURE/meta/manifest.json"
  run bash "$CLI" inspect "$FIXTURE/meta/manifest.json"
  assert_success
  assert_output_contains "Backup inspection"
  assert_output_contains "present"
}

@test "inspect shows checksum verification failed for corrupted checksum file" {
  mkdir -p "$FIXTURE/components/brew"
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
  printf '%s\n' '/Users/tester/.ssh/**' > "$FIXTURE/meta/include-paths.txt"
  printf '%s\n' '**/node_modules/**' > "$FIXTURE/meta/exclude-patterns.txt"
  write_run_json "$FIXTURE/meta/run.json" 2026-03-25T00:00:00Z 2026-03-25T00:00:00Z 2026-03-25T00:10:00Z completed /Volumes/Test "$FIXTURE" tester /Users/tester
  write_manifest_json "$FIXTURE/meta/manifest.json" "$FIXTURE" false true false false false remap_to_target_home preserve_system_remap_user
  mkdir -p "$FIXTURE/meta/integrity"
  printf '%s\n' 'deadbeef  /tmp/nope.json' > "$FIXTURE/meta/integrity/manifest.sha256"

  run bash "$CLI" inspect "$FIXTURE/meta/manifest.json"
  assert_success
  assert_output_contains "checksum verification failed"
}
