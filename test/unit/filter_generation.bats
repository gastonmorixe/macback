#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "generate_rclone_filter appends final catch-all exclude" {
  local workdir="$BATS_TEST_TMPDIR/filter"
  mkdir -p "$workdir"
  printf '%s\n' "$MACBACK_PRIMARY_HOME/.ssh/**" > "$workdir/include.txt"
  printf '%s\n' '**/node_modules/**' > "$workdir/exclude.txt"

  run generate_rclone_filter "$workdir/include.txt" "$workdir/exclude.txt" "$workdir/rclone.filter"
  assert_success
  assert_file_exists "$workdir/rclone.filter"
  assert_file_contains "$workdir/rclone.filter" "- **"
  assert_file_contains "$workdir/rclone.filter" "+ $MACBACK_PRIMARY_HOME/.ssh/**"
}
