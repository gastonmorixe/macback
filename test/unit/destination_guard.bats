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

@test "run_with_destination_guard stops the child when destination changes" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"

    local_guard_file="$BATS_TEST_TMPDIR/guard.present"
    local_pid_file="$BATS_TEST_TMPDIR/child.pid"
    local_failure_file="$BATS_TEST_TMPDIR/guard.failure"
    : > "$local_guard_file"

    destination_capture_guard() {
      printf "/Volumes/Test Disk\tUUID-123\t424242\n"
    }
    destination_matches_guard() {
      [[ -f "$local_guard_file" ]]
    }
    sleep() {
      command sleep 0.05
    }
    guarded_child() {
      printf "%s\n" "$BASHPID" > "$local_pid_file"
      while true; do
        command sleep 0.05
      done
    }

    (
      command sleep 0.20
      rm -f "$local_guard_file"
    ) &

    set +e
    run_with_destination_guard "/Volumes/Test Disk/run" "$local_failure_file" guarded_child
    echo status:$?

    if [[ -f "$local_failure_file" ]]; then
      echo failure:yes
    else
      echo failure:no
    fi

    if [[ -f "$local_pid_file" ]]; then
      child_pid="$(cat "$local_pid_file")"
      if kill -0 "$child_pid" 2>/dev/null; then
        echo child:alive
      else
        echo child:stopped
      fi
    else
      echo child:missing
    fi
  '

  assert_success
  assert_output_contains "status:75"
  assert_output_contains "failure:yes"
  assert_output_contains "child:stopped"
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
