#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "select_destination_base returns selected discovered volume in plain mode" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"
    MACBACK_PLAIN_UI=1
    discover_destination_roots() { printf "%s\n" /Volumes/A /Volumes/B; }
    printf "1\n" | select_destination_base
  '
  assert_success
  assert_output_contains "/Volumes/A"
}

@test "select_destination_base accepts custom path in plain mode" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"
    MACBACK_PLAIN_UI=1
    discover_destination_roots() { printf "%s\n" /Volumes/A /Volumes/B; }
    printf "3\n/tmp/custom-dest\n" | select_destination_base
  '
  assert_success
  assert_output_contains "/tmp/custom-dest"
}

@test "select_destination_base supports back in plain mode" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"
    MACBACK_PLAIN_UI=1
    discover_destination_roots() { printf "%s\n" /Volumes/A /Volumes/B; }
    printf "4\n" | select_destination_base
  '
  assert_failure
}
