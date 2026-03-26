#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "choose_component_flags deselects requested items in plain mode" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"
    MACBACK_PLAIN_UI=1
    printf "2,4\n" | choose_component_flags
  '
  assert_success
  assert_output_contains $'yes\tno\tyes\tno\tyes'
}

@test "select_backup_components deselects unavailable selections in plain mode" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"
    MACBACK_PLAIN_UI=1
    printf "2\n" | select_backup_components yes yes yes
  '
  assert_success
  assert_output_contains $'yes\tno\tyes'
}
