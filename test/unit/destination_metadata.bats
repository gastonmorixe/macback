#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "destination_is_real_mount rejects /Volumes folders that are not the actual mount point" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"
    destination_diskutil_info() {
      case "$1" in
        "/Volumes/ST1000LM1TB")
          cat <<EOF
   Mounted: Yes
   Mount Point: /Volumes/ST1000LM1TB
EOF
          ;;
        "/Volumes/ST1000LM1TB ")
          cat <<EOF
   Mounted: Yes
   Mount Point: /System/Volumes/Data
EOF
          ;;
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
    destination_diskutil_info() {
      cat <<EOF
   Device Node: /dev/disk12s2
   Type (Bundle): exfat
   Device Location: External
   Protocol: USB
EOF
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

@test "discover_destination_roots skips non-local mounts before probing diskutil" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"

    mount() {
      cat <<EOF
/dev/disk11s1 on /Volumes/GASTON (apfs, local, nodev, nosuid, journaled, noowners)
//gaston@rpi5._smb._tcp.local/PI5SHARE on /Volumes/PI5SHARE (smbfs, nodev, nosuid, mounted by gaston)
EOF
    }
    destination_mount_is_local() {
      [[ "$1" == "/Volumes/GASTON" ]]
    }
    destination_is_real_mount() {
      [[ "$1" == "/Volumes/GASTON" ]]
    }
    destination_diskutil_value() {
      local path="$1"
      local key="$2"
      case "$path|$key" in
        "/Volumes/GASTON|^ *Mounted$") echo "Yes" ;;
        "/Volumes/GASTON|^ *Mount Point$") echo "/Volumes/GASTON" ;;
        "/Volumes/PI5SHARE|^ *Mounted$") echo "should-not-probe" ;;
      esac
    }

    discover_destination_roots
  '
  assert_success
  assert_output_contains "/Volumes/GASTON"
  [[ "$output" != *"PI5SHARE"* ]]
}

@test "destination_capture_guard uses the mounted volume root and device identity" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"
    destination_diskutil_info() {
      cat <<EOF
   Mounted: Yes
   Mount Point: /Volumes/ST1000LM1TB 2
   Volume UUID: UUID-123
EOF
    }
    destination_path_device_id() {
      echo "424242"
    }
    destination_capture_guard "/Volumes/ST1000LM1TB 2/backups/run-1"
  '
  assert_success
  assert_output_contains $'/Volumes/ST1000LM1TB 2\tUUID-123\t424242'
}

@test "find_destination_by_volume_uuid returns the currently mounted matching volume" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"
    discover_destination_roots() {
      printf "%s\n" "/Volumes/Other Disk" "/Volumes/ST1000LM1TB 2"
    }
    destination_diskutil_value() {
      local path="$1"
      local key="$2"
      case "$path|$key" in
        "/Volumes/Other Disk|^ *Volume UUID$") echo "UUID-OTHER" ;;
        "/Volumes/ST1000LM1TB 2|^ *Volume UUID$") echo "UUID-123" ;;
      esac
    }
    find_destination_by_volume_uuid "UUID-123"
  '
  assert_success
  assert_output_contains "/Volumes/ST1000LM1TB 2"
}

@test "create_run_dir rejects stale /Volumes base paths" {
  run env MACBACK_ROOT="$MACBACK_ROOT" bash -lc '
    source "$MACBACK_ROOT/macback"
    destination_capture_guard() {
      return 1
    }
    create_run_dir "/Volumes/ST1000LM1TB 1"
  '
  assert_failure
  assert_output_contains "Destination is not a live mounted volume"
}
