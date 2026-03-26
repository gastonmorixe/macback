#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "run_with_destination_guard returns child status when destination stays valid" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"
    destination_capture_guard() {
      printf "/Volumes/Test Disk\tUUID-123\t424242\n"
    }
    destination_matches_guard() {
      return 0
    }

    set +e
    run_with_destination_guard "/Volumes/Test Disk/run" "$BATS_TEST_TMPDIR/guard.failure" bash -lc "exit 23"
    echo status:$?
    if [[ -f "$BATS_TEST_TMPDIR/guard.failure" ]]; then
      echo failure:yes
    else
      echo failure:no
    fi
  '

  assert_success
  assert_output_contains "status:23"
  assert_output_contains "failure:no"
}

@test "run_with_destination_guard returns guard status when destination capture fails" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"

    destination_capture_guard() {
      return 1
    }
    guarded_child() {
      printf "started\n" > "$BATS_TEST_TMPDIR/child.started"
    }
    set +e
    run_with_destination_guard "/Volumes/Test Disk/run" "$BATS_TEST_TMPDIR/guard.failure" guarded_child
    echo status:$?
    if [[ -f "$BATS_TEST_TMPDIR/child.started" ]]; then
      echo child:started
    else
      echo child:not-started
    fi
  '

  assert_success
  assert_output_contains "status:75"
  assert_output_contains "child:not-started"
}

@test "pause_for_destination_change can continue on the same volume remounted elsewhere" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"
    find_destination_by_volume_uuid() {
      printf "/Volumes/ST1000LM1TB 2\n"
    }

    printf "1\n" | pause_for_destination_change \
      "/Volumes/ST1000LM1TB 1" \
      "/Volumes/ST1000LM1TB 1/macback/machine/20260325-120000" \
      "UUID-123"
  '

  assert_success
  assert_output_contains $'/Volumes/ST1000LM1TB 2\t/Volumes/ST1000LM1TB 2/macback/machine/20260325-120000'
}

@test "pause_for_destination_change can stop when the destination is unavailable" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"
    find_destination_by_volume_uuid() {
      return 1
    }

    printf "2\n" | pause_for_destination_change \
      "/Volumes/ST1000LM1TB 1" \
      "/Volumes/ST1000LM1TB 1/macback/machine/20260325-120000" \
      "UUID-123"
  '

  assert_failure
}
