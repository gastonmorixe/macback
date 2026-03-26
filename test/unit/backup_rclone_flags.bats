#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "backup_files_component uses inplace writes and metadata when supported" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"

    run_dir="$BATS_TEST_TMPDIR/run"
    meta_dir="$run_dir/meta"
    mkdir -p "$meta_dir"
    printf "%s\n" "/Users/tester/.ssh/**" > "$meta_dir/include.txt"
    printf "%s\n" "**/node_modules/**" > "$meta_dir/exclude.txt"

    call_dir="$BATS_TEST_TMPDIR/calls"
    mkdir -p "$call_dir"
    call_index=0

    build_dynamic_excludes() {
      : > "$2"
    }
    generate_rclone_filter() {
      printf "%s\n" "+ /Users/tester/.ssh/**" "- **" > "$3"
    }
    path_supports_metadata() {
      return 0
    }
    write_permissions_inventory() {
      : > "$2"
    }
    run_with_destination_guard() {
      call_index=$((call_index + 1))
      printf "%s\n" "$@" > "$call_dir/$call_index.txt"
      return 0
    }

    backup_files_component "$run_dir" "$meta_dir/include.txt" "$meta_dir/exclude.txt" "$BATS_TEST_TMPDIR/guard.error"

    printf "copy-call\n"
    cat "$call_dir/1.txt"
    printf "check-call\n"
    cat "$call_dir/2.txt"
  '

  assert_success
  assert_output_contains "copy-call"
  assert_output_contains "rclone"
  assert_output_contains "copy"
  assert_output_contains "--inplace"
  assert_output_contains "--metadata"
  assert_output_contains "check-call"
  assert_output_contains "check"
}

@test "backup_files_component skips rclone check on resume mode" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"

    run_dir="$BATS_TEST_TMPDIR/run"
    meta_dir="$run_dir/meta"
    integrity_dir="$meta_dir/integrity"
    mkdir -p "$integrity_dir"
    printf "%s\n" "/Users/tester/.ssh/**" > "$meta_dir/include.txt"
    printf "%s\n" "**/node_modules/**" > "$meta_dir/exclude.txt"

    call_dir="$BATS_TEST_TMPDIR/calls"
    mkdir -p "$call_dir"
    call_index=0

    build_dynamic_excludes() {
      : > "$2"
    }
    generate_rclone_filter() {
      printf "%s\n" "+ /Users/tester/.ssh/**" "- **" > "$3"
    }
    path_supports_metadata() {
      return 0
    }
    write_permissions_inventory() {
      : > "$2"
    }
    run_with_destination_guard() {
      call_index=$((call_index + 1))
      printf "%s\n" "$@" > "$call_dir/$call_index.txt"
      return 0
    }

    backup_files_component "$run_dir" "$meta_dir/include.txt" "$meta_dir/exclude.txt" "$BATS_TEST_TMPDIR/guard.error" resume

    printf "calls:%s\n" "$call_index"
    printf "check-status:%s\n" "$(cat "$integrity_dir/rclone-check.exit-code")"
  '

  assert_success
  assert_output_contains "calls:1"
  assert_output_contains "check-status:skipped-resume-fast"
}
