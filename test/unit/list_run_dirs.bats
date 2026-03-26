#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "list_run_dirs finds runs by run.env" {
  local base="$BATS_TEST_TMPDIR/volumes/TestDisk/macback"
  local run1="$base/machine1/20260325-100000"
  local run2="$base/machine1/20260325-120000"
  mkdir -p "$run1/meta" "$run2/meta"
  printf 'STATUS=completed\n' > "$run1/meta/run.env"
  printf 'STATUS=running\n' > "$run2/meta/run.env"

  run list_run_dirs "$BATS_TEST_TMPDIR/volumes/TestDisk/macback"
  assert_success
  [[ "$output" == *"20260325-100000"* ]]
  [[ "$output" == *"20260325-120000"* ]]
}

@test "list_run_dirs ignores dirs without run.env" {
  local base="$BATS_TEST_TMPDIR/volumes/TestDisk2/macback"
  local run1="$base/machine1/20260325-100000"
  local stray="$base/machine1/random-dir"
  mkdir -p "$run1/meta" "$stray/meta"
  printf 'STATUS=completed\n' > "$run1/meta/run.env"

  run list_run_dirs "$BATS_TEST_TMPDIR/volumes/TestDisk2/macback"
  assert_success
  [[ "$output" == *"20260325-100000"* ]]
  [[ "$output" != *"random-dir"* ]]
}
