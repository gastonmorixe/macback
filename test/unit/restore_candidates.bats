#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "discover_user_restore_candidates groups preferences and app config paths" {
  local user_root="$BATS_TEST_TMPDIR/source-user"
  mkdir -p "$user_root/Library/Preferences" "$user_root/Library/Application Support/iTerm" "$user_root/.config/gh" "$user_root/Library/LaunchAgents"
  touch "$user_root/Library/Preferences/com.googlecode.iterm2.plist"
  touch "$user_root/Library/LaunchAgents/com.user.dev-env-path.plist"

  run discover_user_restore_candidates "$user_root" "$BATS_TEST_TMPDIR/candidates.txt"
  assert_success
  assert_file_contains "$BATS_TEST_TMPDIR/candidates.txt" "/Library/Preferences/com.googlecode.iterm2.plist"
  assert_file_contains "$BATS_TEST_TMPDIR/candidates.txt" "/Library/Application Support/iTerm/**"
  assert_file_contains "$BATS_TEST_TMPDIR/candidates.txt" "/.config/gh/**"
  assert_file_contains "$BATS_TEST_TMPDIR/candidates.txt" "/Library/LaunchAgents/com.user.dev-env-path.plist"
}
