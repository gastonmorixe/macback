#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
  CLI="$MACBACK_ROOT/macback"
}

@test "macback help exits 0" {
  run bash "$CLI" help
  assert_success
}

@test "macback help mentions restore" {
  run bash "$CLI" help
  assert_success
  assert_output_contains "macback restore"
}
