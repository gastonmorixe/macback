#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "restore_brew_component shows install guidance and skips in non-interactive mode when brew is missing" {
  local run_dir="$BATS_TEST_TMPDIR/run"
  mkdir -p "$run_dir/components/brew"
  printf '%s\n' 'tap "homebrew/core"' 'brew "jq"' > "$run_dir/components/brew/Brewfile"
  printf '%s\n' 'jq' > "$run_dir/components/brew/formulae.txt"
  : > "$run_dir/components/brew/casks.txt"

  RESTORE_TARGET_USER="tester"
  PATH="/usr/bin:/bin"

  run restore_brew_component "$run_dir"
  [[ "$status" -eq 2 ]]
  assert_output_contains "Homebrew is not installed"
  assert_output_contains "tester"
}
