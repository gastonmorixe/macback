#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
  CLI="$MACBACK_ROOT/macback"
}

@test "macback unknown command exits nonzero" {
  run bash "$CLI" nope
  assert_failure
  assert_output_contains "Unknown command"
}

@test "macback backup requires root" {
  run bash "$CLI" backup
  assert_failure
  assert_output_contains "must run as root"
}

@test "macback restore requires root" {
  run bash "$CLI" restore
  assert_failure
  assert_output_contains "must run as root"
}
