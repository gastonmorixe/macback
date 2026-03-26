#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "select_backup_manifest accepts custom path in plain mode" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"
    MACBACK_PLAIN_UI=1
    list_run_manifests() { printf "%s\n" /tmp/one/meta/manifest.json /tmp/two/meta/manifest.json; }
    printf "3\n/tmp/custom-run\n" | select_backup_manifest
  '
  assert_success
  assert_output_contains "/tmp/custom-run"
}

@test "select_backup_manifest supports back in plain mode" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"
    MACBACK_PLAIN_UI=1
    list_run_manifests() { printf "%s\n" /tmp/one/meta/manifest.json; }
    printf "3\n" | select_backup_manifest
  '
  assert_failure
}
