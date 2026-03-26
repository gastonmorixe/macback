#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "backup_launchd_metadata writes scoped restore lists and system reference inventory" {
  local home="$BATS_TEST_TMPDIR/home"
  local run="$BATS_TEST_TMPDIR/run"
  mkdir -p "$home/Library/LaunchAgents" "$run"
  export MACBACK_PRIMARY_HOME="$home"
  touch "$home/Library/LaunchAgents/com.user.dev-env-path.plist"

  run backup_launchd_metadata "$run"
  assert_success
  assert_file_exists "$run/components/launchd/user-launchagents.txt"
  assert_file_exists "$run/components/launchd/custom-system-plists.txt"
  assert_file_exists "$run/components/launchd/all-system-plists-reference.txt"
  assert_file_contains "$run/components/launchd/user-launchagents.txt" "$home/Library/LaunchAgents/com.user.dev-env-path.plist"
}
