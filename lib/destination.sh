#!/usr/bin/env bash

discover_destination_roots() {
  if [[ -n "${MACBACK_TEST_DESTINATIONS:-}" ]]; then
    printf '%s\n' "$MACBACK_TEST_DESTINATIONS"
    return 0
  fi
  local seen=""
  local volume
  for volume in /Volumes/*; do
    [[ -e "$volume" ]] || continue
    [[ -L "$volume" ]] && continue
    local trimmed
    trimmed="$(trim_trailing_space "$volume")"
    case "$(basename "$trimmed")" in
      .timemachine|com.apple.TimeMachine.localsnapshots|Macintosh\ HD|Backups\ of\ *) continue ;;
    esac
    if [[ "$volume" != "$trimmed" && -e "$trimmed" ]]; then
      continue
    fi
    if ! destination_is_real_mount "$trimmed"; then
      continue
    fi
    case "
$seen
" in
      *"
$trimmed
"*) continue ;;
    esac
    seen="${seen}${trimmed}"$'\n'
    printf '%s\n' "$trimmed"
  done
}

destination_diskutil_value() {
  local path="$1"
  local key="$2"
  diskutil info "$path" 2>/dev/null | awk -F': *' -v k="$key" '$1 ~ k {print $2; exit}'
}

destination_is_real_mount() {
  local path="$1"
  local mounted mount_point
  mounted="$(destination_diskutil_value "$path" '^ *Mounted$')"
  mount_point="$(destination_diskutil_value "$path" '^ *Mount Point$')"
  [[ "$mounted" == "Yes" ]] || return 1
  [[ "$mount_point" == "$path" ]]
}

destination_volume_root_for_path() {
  local path="$1"
  [[ "$path" == /Volumes/* ]] || return 1
  local remainder="${path#/Volumes/}"
  local volume_name="${remainder%%/*}"
  [[ -n "$volume_name" ]] || return 1
  printf '/Volumes/%s\n' "$volume_name"
}

destination_requires_mount_guard() {
  [[ "$1" == /Volumes/* ]]
}

destination_path_device_id() {
  stat -f '%d' "$1" 2>/dev/null
}

destination_capture_guard() {
  local path="$1"
  destination_requires_mount_guard "$path" || return 1

  local guard_path volume_uuid device_id
  guard_path="$(destination_volume_root_for_path "$path")" || return 1
  destination_is_real_mount "$guard_path" || return 1
  volume_uuid="$(destination_diskutil_value "$guard_path" '^ *Volume UUID$')"
  device_id="$(destination_path_device_id "$guard_path")" || return 1
  [[ -n "$device_id" ]] || return 1
  printf '%s\t%s\t%s\n' "$guard_path" "$volume_uuid" "$device_id"
}

find_destination_by_volume_uuid() {
  local expected_uuid="$1"
  [[ -n "$expected_uuid" ]] || return 1

  local volume current_uuid
  while IFS= read -r volume; do
    current_uuid="$(destination_diskutil_value "$volume" '^ *Volume UUID$')"
    [[ "$current_uuid" == "$expected_uuid" ]] || continue
    printf '%s\n' "$volume"
    return 0
  done < <(discover_destination_roots)
  return 1
}

destination_matches_guard() {
  local guard_path="$1"
  local expected_uuid="$2"
  local expected_device_id="$3"
  destination_is_real_mount "$guard_path" || return 1

  local current_device_id current_uuid=""
  current_device_id="$(destination_path_device_id "$guard_path")" || return 1
  [[ "$current_device_id" == "$expected_device_id" ]] || return 1

  if [[ -n "$expected_uuid" ]]; then
    current_uuid="$(destination_diskutil_value "$guard_path" '^ *Volume UUID$')"
    [[ "$current_uuid" == "$expected_uuid" ]] || return 1
  fi
}

destination_assert_write_target() {
  local path="$1"
  if ! destination_requires_mount_guard "$path"; then
    return 0
  fi
  destination_capture_guard "$path" >/dev/null || {
    echo "Destination is not a live mounted volume: $path" >&2
    return 1
  }
}

destination_rebind_to_volume_root() {
  local path="$1"
  local new_root="$2"
  local old_root
  old_root="$(destination_volume_root_for_path "$path")" || return 1
  printf '%s%s\n' "$new_root" "${path#$old_root}"
}

describe_destination() {
  local path="$1"
  local label
  local device_node fs_type location protocol writable
  label="$(basename "$path")"
  device_node="$(destination_diskutil_value "$path" '^ *Device Node$')"
  fs_type="$(destination_diskutil_value "$path" '^ *Type \(Bundle\)$')"
  if [[ -z "$fs_type" || "$fs_type" == "unknown" ]]; then
    fs_type="$(mount | grep -F " on $path (" | sed 's/.*(\([^,]*\).*/\1/' || true)"
  fi
  location="$(destination_diskutil_value "$path" '^ *Device Location$')"
  protocol="$(destination_diskutil_value "$path" '^ *Protocol$')"
  [[ -w "$path" ]] && writable="writable" || writable="read-only"
  printf '%s (%s)|%s • %s • %s • %s|%s\n' \
    "$label" \
    "${device_node:-unknown-device}" \
    "${fs_type:-unknown-fs}" \
    "${location:-unknown-location}" \
    "${protocol:-unknown-protocol}" \
    "$writable" \
    "$path"
}

select_destination_base() {
  local options=()
  local option
  local volume
  while IFS= read -r volume; do
    option="$(describe_destination "$volume")"
    options+=("$option")
  done < <(discover_destination_roots)
  options+=("Custom path")
  options+=("Back")

  local chosen
  chosen="$(choose_from_lines "Backup destination" "${options[@]}")" || return 1
  if [[ "$chosen" == "Back" ]]; then
    return 1
  fi
  if [[ "$chosen" == "Custom path" ]]; then
    prompt "Custom destination path"
    ui_read_prompt_line
    chosen="${REPLY//\\ / }"
    [[ -n "$chosen" ]] || return 1
    printf '%s\n' "$chosen"
    return 0
  fi

  local rendered
  for rendered in "${options[@]}"; do
    if [[ "${rendered%%|*}" == "$chosen" ]]; then
      printf '%s\n' "${rendered##*|}"
      return 0
    fi
  done
  return 1
}

create_run_dir() {
  local base="$1"
  destination_assert_write_target "$base" || return 1
  local machine_id
  machine_id="$(detect_machine_id)"
  local run_id
  run_id="$(timestamp_id)"
  local run_dir="$base/macback/$machine_id/$run_id"
  ensure_dir "$run_dir"
  printf '%s\n' "$run_dir"
}

find_latest_run_dir() {
  local base="$1"
  destination_assert_write_target "$base" || return 1
  local machine_id
  machine_id="$(detect_machine_id)"
  local machine_root="$base/macback/$machine_id"
  if [[ -d "$machine_root" ]]; then
    find "$machine_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1
    return 0
  fi

  local root="$base/macback"
  [[ -d "$root" ]] || return 1
  find "$root" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort | tail -1
}

choose_run_dir_for_backup() {
  local base="$1"
  local latest_run=""
  latest_run="$(find_latest_run_dir "$base" 2>/dev/null || true)"

  if [[ -z "$latest_run" ]]; then
    printf 'new\t%s\n' "$(create_run_dir "$base")"
    return 0
  fi

  local active_pid=""
  if [[ -f "$latest_run/meta/active.pid" ]]; then
    active_pid="$(cat "$latest_run/meta/active.pid" 2>/dev/null || true)"
  fi
  local resume_desc="Reuse $latest_run and repair any missing or failed files"
  if pid_is_running "$active_pid"; then
    resume_desc="A backup appears to still be running there (pid $active_pid)"
  fi
  local options=(
    "Resume latest run|$resume_desc"
    "Create new run|Create a fresh timestamped backup run"
    "Back|Return to the previous menu"
  )

  local choice
  choice="$(choose_from_lines "Existing backup found" "${options[@]}")" || return 1
  case "$choice" in
    Resume\ latest\ run)
      if pid_is_running "$active_pid"; then
        warn "A backup process is still active for $latest_run."
        return 1
      fi
      printf 'resume\t%s\n' "$latest_run"
      ;;
    Create\ new\ run) printf 'new\t%s\n' "$(create_run_dir "$base")" ;;
    Back) return 1 ;;
    *) return 1 ;;
  esac
}

select_backup_manifest() {
  local roots=()
  local manifest
  local count=0
  local truncated=false
  while IFS= read -r manifest; do
    count=$((count + 1))
    if (( ${#roots[@]} >= MACBACK_MAX_MANIFEST_CHOICES )); then
      truncated=true
      continue
    fi
    roots+=("$manifest")
  done < <(list_run_manifests /Volumes)
  roots+=("Custom path")
  roots+=("Back")

  if $truncated; then
    warn "Showing only the first ${MACBACK_MAX_MANIFEST_CHOICES} discovered backups. Use Custom path to target another backup."
  fi

  local chosen
  chosen="$(choose_from_lines "Restore source" "${roots[@]}")" || return 1
  if [[ "$chosen" == "Back" ]]; then
    return 1
  fi
  if [[ "$chosen" == "Custom path" ]]; then
    prompt "Path to backup run directory"
    ui_read_prompt_line
    chosen="${REPLY//\\ / }"
    [[ -n "$chosen" ]] || return 1
  fi

  if [[ -d "$chosen" ]]; then
    chosen="$chosen/meta/manifest.json"
  fi
  printf '%s\n' "$chosen"
}

select_backup_run_dir() {
  local dirs=()
  local run_dir
  while IFS= read -r run_dir; do
    [[ -n "$run_dir" ]] || continue
    local label status_hint
    label="$(basename "$(dirname "$run_dir")")/$(basename "$run_dir")"
    if [[ -f "$run_dir/meta/manifest.json" ]]; then
      status_hint="complete"
    else
      status_hint="incomplete"
    fi
    dirs+=("$label|$status_hint|$run_dir")
  done < <(list_run_dirs /Volumes)
  dirs+=("Custom path")
  dirs+=("Back")

  local chosen
  chosen="$(choose_from_lines "Select backup" "${dirs[@]}")" || return 1
  if [[ "$chosen" == "Back" ]]; then
    return 1
  fi
  if [[ "$chosen" == "Custom path" ]]; then
    prompt "Path to backup run directory"
    ui_read_prompt_line
    chosen="${REPLY//\\ / }"
    [[ -n "$chosen" ]] || return 1
    printf '%s\n' "$chosen"
    return 0
  fi

  local entry
  for entry in "${dirs[@]}"; do
    if [[ "${entry%%|*}" == "$chosen" ]]; then
      printf '%s\n' "${entry##*|}"
      return 0
    fi
  done
  return 1
}
