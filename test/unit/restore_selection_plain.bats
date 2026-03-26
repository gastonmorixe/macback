#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "select_restore_rules keeps selected restore paths in plain mode" {
  local includes="$BATS_TEST_TMPDIR/includes.txt"
  local selected="$BATS_TEST_TMPDIR/selected.txt"
  printf '%s\n' "/Users/tester/.ssh/**" "/Users/tester/.config/**" "/Library/LaunchDaemons/com.local.test.plist" > "$includes"

  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc "
    source \"\$MACBACK_ROOT/macback\"
    MACBACK_PLAIN_UI=1
    printf '2\n' | select_restore_rules '$includes' '$selected'
  "
  assert_success
  assert_file_contains "$selected" "/Users/tester/.ssh/**"
  assert_file_contains "$selected" "/Library/LaunchDaemons/com.local.test.plist"
}

@test "select_granular_restore_excludes writes deselected items to extra excludes in plain mode" {
  local candidates="$BATS_TEST_TMPDIR/candidates.txt"
  local extra="$BATS_TEST_TMPDIR/extra.txt"
  printf '%s\n' "/Library/Preferences/com.googlecode.iterm2.plist" "/Library/Preferences/com.other.app.plist" > "$candidates"

  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc "
    source \"\$MACBACK_ROOT/macback\"
    MACBACK_PLAIN_UI=1
    printf '2\n' | select_granular_restore_excludes '$candidates' '$extra'
  "
  assert_success
  assert_file_contains "$candidates" "/Library/Preferences/com.googlecode.iterm2.plist"
  assert_file_contains "$extra" "/Library/Preferences/com.other.app.plist"
}

@test "choose_brew_restore_items deselects items in plain mode" {
  local selection="$BATS_TEST_TMPDIR/brew-selection.txt"
  printf '%s\n' $'brew\tjq' $'brew\tfd' $'cask\titerm2' > "$selection"

  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc "
    source \"\$MACBACK_ROOT/macback\"
    MACBACK_PLAIN_UI=1
    printf '2\n' | choose_brew_restore_items '$selection'
  "
  assert_success
  assert_file_contains "$selection" $'brew\tjq'
  assert_file_contains "$selection" $'cask\titerm2'
}
