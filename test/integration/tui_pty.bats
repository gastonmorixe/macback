#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
  ROOT="$MACBACK_ROOT"
  if [[ -z "${MACBACK_ENABLE_PTY_TESTS:-}" ]]; then
    skip "Set MACBACK_ENABLE_PTY_TESTS=1 to run PTY/TUI integration tests."
  fi
}

@test "PTY main menu navigation works" {
  run expect "$ROOT/test/pty/main_menu.exp" "$ROOT"
  assert_success
}

@test "PTY prompt input ignores arrow key escape printing" {
  run expect "$ROOT/test/pty/prompt_arrows.exp" "$ROOT"
  assert_success
}
