#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "template resolution expands @HOME@" {
  local tmpdir="$BATS_TEST_TMPDIR/templates"
  mkdir -p "$tmpdir"

  run seed_effective_rules "$tmpdir" "$MACBACK_PRIMARY_HOME"
  assert_success
  assert_file_exists "$tmpdir/include-paths.txt"
  assert_file_contains "$tmpdir/include-paths.txt" "$MACBACK_PRIMARY_HOME/.ssh/**"
  assert_file_contains "$tmpdir/include-paths.txt" "$MACBACK_PRIMARY_HOME/.config/fish/**"
  assert_file_contains "$tmpdir/include-paths.txt" "$MACBACK_PRIMARY_HOME/.zprofile"
  assert_file_contains "$tmpdir/exclude-patterns.txt" "$MACBACK_PRIMARY_HOME/Library/Mobile Documents/**"
  assert_file_contains "$tmpdir/exclude-patterns.txt" "$MACBACK_PRIMARY_HOME/Library/CloudStorage/**"
}
