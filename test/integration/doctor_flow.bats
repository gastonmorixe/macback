#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
  CLI="$MACBACK_ROOT/macback"
  FIXTURE="$BATS_TEST_TMPDIR/doctor-run"
  mkdir -p "$FIXTURE/meta/integrity" "$FIXTURE/components/files/rootfs" "$FIXTURE/components/brew" "$FIXTURE/components/system"
  printf '%s\n' 'tap "homebrew/core"' > "$FIXTURE/components/brew/Brewfile"
  write_run_env "$FIXTURE/meta/run.env" \
    SPEC_VERSION 1 TOOL_VERSION 0.1.0 \
    CREATED_AT 2026-03-25T00:00:00Z STARTED_AT 2026-03-25T00:00:00Z \
    FINISHED_AT 2026-03-25T00:10:00Z STATUS completed \
    DESTINATION_BASE /Volumes/Test RUN_DIR "$FIXTURE" \
    SOURCE_USER tester SOURCE_HOME /Users/tester
  write_run_json "$FIXTURE/meta/run.json" 2026-03-25T00:00:00Z 2026-03-25T00:00:00Z 2026-03-25T00:10:00Z completed /Volumes/Test "$FIXTURE" tester /Users/tester
  printf '%s\n' '/Users/tester/.ssh/**' > "$FIXTURE/meta/include-paths.txt"
  printf '%s\n' '**/node_modules/**' > "$FIXTURE/meta/exclude-patterns.txt"
  write_manifest_json "$FIXTURE/meta/manifest.json" "$FIXTURE" true true false true false remap_to_target_home preserve_system_remap_user
  write_integrity_checksums "$FIXTURE/meta/integrity" "$FIXTURE/meta/run.json" "$FIXTURE/meta/manifest.json"
  printf '0\n' > "$FIXTURE/meta/integrity/rclone-copy.exit-code"
  printf '0\n' > "$FIXTURE/meta/integrity/rclone-check.exit-code"
}

@test "doctor reports no issues on healthy backup" {
  run bash "$CLI" doctor "$FIXTURE"
  assert_success
  assert_output_contains "Backup doctor"
  assert_output_contains "No issues found"
}

@test "doctor detects missing manifest.json" {
  rm -f "$FIXTURE/meta/manifest.json"
  run bash "$CLI" doctor "$FIXTURE"
  assert_success
  assert_output_contains "MISSING"
  assert_output_contains "issue(s) remaining"
}

@test "doctor detects rclone copy failure" {
  printf '1\n' > "$FIXTURE/meta/integrity/rclone-copy.exit-code"
  run bash "$CLI" doctor "$FIXTURE"
  assert_success
  assert_output_contains "FAILED (exit 1)"
  assert_output_contains "issue(s) remaining"
}

@test "doctor detects rclone check warnings" {
  printf '2\n' > "$FIXTURE/meta/integrity/rclone-check.exit-code"
  run bash "$CLI" doctor "$FIXTURE"
  assert_success
  assert_output_contains "WARNINGS (exit 2)"
}

@test "doctor reports skipped fast-resume verification without warning" {
  printf 'skipped-resume-fast\n' > "$FIXTURE/meta/integrity/rclone-check.exit-code"
  run bash "$CLI" doctor "$FIXTURE"
  assert_success
  assert_output_contains "skipped for fast resume"
  assert_output_contains "No issues found"
}

@test "doctor reports skipped fast profile verification without warning" {
  printf 'skipped-speed-fast\n' > "$FIXTURE/meta/integrity/rclone-check.exit-code"
  run bash "$CLI" doctor "$FIXTURE"
  assert_success
  assert_output_contains "skipped by Fast profile"
  assert_output_contains "No issues found"
}

@test "doctor shows component status" {
  run bash "$CLI" doctor "$FIXTURE"
  assert_success
  assert_output_contains "Files"
  assert_output_contains "present"
  assert_output_contains "Homebrew"
  assert_output_contains "System"
}

@test "doctor rejects nonexistent directory" {
  run bash "$CLI" doctor "/nonexistent/path"
  assert_failure
  assert_output_contains "not found"
}
