#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "destination_is_real_mount rejects /Volumes folders that are not the actual mount point" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"
    destination_diskutil_value() {
      local path="$1"
      local key="$2"
      case "$path|$key" in
        "/Volumes/ST1000LM1TB|^ *Mounted$") echo "Yes" ;;
        "/Volumes/ST1000LM1TB|^ *Mount Point$") echo "/Volumes/ST1000LM1TB" ;;
        "/Volumes/ST1000LM1TB |^ *Mounted$") echo "Yes" ;;
        "/Volumes/ST1000LM1TB |^ *Mount Point$") echo "/System/Volumes/Data" ;;
      esac
    }
    set +e
    destination_is_real_mount "/Volumes/ST1000LM1TB"
    echo first:$?
    destination_is_real_mount "/Volumes/ST1000LM1TB "
    echo second:$?
  '
  assert_success
  assert_output_contains "first:0"
  assert_output_contains "second:1"
}

@test "describe_destination includes device and filesystem metadata" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"
    destination_diskutil_value() {
      local path="$1"
      local key="$2"
      case "$key" in
        "^ *Device Node$") echo "/dev/disk12s2" ;;
        "^ *Type \(Bundle\)$") echo "exfat" ;;
        "^ *Device Location$") echo "External" ;;
        "^ *Protocol$") echo "USB" ;;
      esac
    }
    test -w /tmp
    describe_destination /tmp
  '
  assert_success
  assert_output_contains "/dev/disk12s2"
  assert_output_contains "exfat"
  assert_output_contains "External"
  assert_output_contains "USB"
}
