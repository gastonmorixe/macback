#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
  CLI="$MACBACK_ROOT/macback"
  FIXTURE="$BATS_TEST_TMPDIR/serial-fixture"
  mkdir -p "$FIXTURE/meta"
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
    SOURCE_HOME /Users/tester \
    SOURCE_SERIAL TEST-SERIAL-123
  write_run_json "$FIXTURE/meta/run.json" 2026-03-25T00:00:00Z 2026-03-25T00:00:00Z 2026-03-25T00:10:00Z completed /Volumes/Test "$FIXTURE" tester /Users/tester TEST-SERIAL-123
  printf '%s\n' '/Users/tester/.ssh/**' > "$FIXTURE/meta/include-paths.txt"
  printf '%s\n' '**/node_modules/**' > "$FIXTURE/meta/exclude-patterns.txt"
  write_manifest_json "$FIXTURE/meta/manifest.json" "$FIXTURE" false false false false false remap_to_target_home preserve_system_remap_user
  write_integrity_checksums "$FIXTURE/meta/integrity" "$FIXTURE/meta/run.json" "$FIXTURE/meta/manifest.json"
}

@test "inspect shows serial match notice when backup serial matches current machine override" {
  run env MACBACK_MACHINE_SERIAL=TEST-SERIAL-123 bash "$CLI" inspect "$FIXTURE/meta/manifest.json"
  assert_success
  assert_output_contains "Serial"
  assert_output_contains "matches this Mac"
}
