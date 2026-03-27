#!/usr/bin/env bash

backup_system_snapshot() {
  local run_dir="$1"
  local out_dir="$run_dir/components/system"
  ensure_dir "$out_dir"

  {
    echo "created_at=$(timestamp_utc)"
    echo "computer_name=$(scutil --get ComputerName 2>/dev/null || hostname)"
    echo "serial_number=$MACBACK_MACHINE_SERIAL"
    echo "host_name=$(hostname)"
    echo "primary_user=$MACBACK_PRIMARY_USER"
    echo "primary_home=$MACBACK_PRIMARY_HOME"
    echo "tool_version=$MACBACK_TOOL_VERSION"
    echo "spec_version=$MACBACK_SPEC_VERSION"
  } > "$out_dir/system.env"

  sw_vers > "$out_dir/sw_vers.txt"
  rclone version > "$out_dir/rclone-version.txt"
  diskutil list external > "$out_dir/diskutil-external.txt" 2>/dev/null || true
  find /Applications "$MACBACK_PRIMARY_HOME/Applications" -maxdepth 2 -type d -name '*.app' 2>/dev/null | sort > "$out_dir/applications.txt"
}

backup_launchd_metadata() {
  local run_dir="$1"
  local out_dir="$run_dir/components/launchd"
  ensure_dir "$out_dir"

  find "$MACBACK_PRIMARY_HOME/Library/LaunchAgents" -type f -name '*.plist' 2>/dev/null | sort > "$out_dir/user-launchagents.txt" || true
  find /Library/LaunchAgents /Library/LaunchDaemons -type f -name 'com.local*.plist' 2>/dev/null | sort > "$out_dir/custom-system-plists.txt" || true
  find /Library/LaunchAgents /Library/LaunchDaemons -type f -name 'com.user*.plist' 2>/dev/null | sort >> "$out_dir/custom-system-plists.txt" || true
  awk '!seen[$0]++' "$out_dir/custom-system-plists.txt" > "$out_dir/custom-system-plists.txt.tmp" 2>/dev/null || true
  if [[ -f "$out_dir/custom-system-plists.txt.tmp" ]]; then
    mv "$out_dir/custom-system-plists.txt.tmp" "$out_dir/custom-system-plists.txt"
  fi
  find /Library/LaunchAgents /Library/LaunchDaemons -type f -name '*.plist' 2>/dev/null | sort > "$out_dir/all-system-plists-reference.txt" || true
}

backup_keychain_metadata() {
  local run_dir="$1"
  local out_dir="$run_dir/components/keychain"
  ensure_dir "$out_dir"

  security list-keychains -d user > "$out_dir/user-keychains.txt" 2>/dev/null || true
  security list-keychains -d system > "$out_dir/system-keychains.txt" 2>/dev/null || true
  security default-keychain -d user > "$out_dir/default-user-keychain.txt" 2>/dev/null || true

  cat > "$out_dir/README.txt" <<EOF
Keychain backup in v1 is metadata + manual guidance only.
If you want manual export artifacts, place them in this component directory.
EOF
}

backup_homebrew_component() {
  local run_dir="$1"
  local out_dir="$run_dir/components/brew"
  ensure_dir "$out_dir"

  if ! has_cmd brew; then
    warn "Homebrew not found; skipping brew component."
    return 1
  fi

  export HOMEBREW_NO_AUTO_UPDATE=1
  export HOMEBREW_NO_ENV_HINTS=1

  run_as_user_capture "$MACBACK_PRIMARY_USER" env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 brew config > "$out_dir/brew-config.txt"
  # shellcheck disable=SC2016
  run_as_user_capture "$MACBACK_PRIMARY_USER" bash -lc 'tmp=$(mktemp); HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 brew bundle dump --force --file "$tmp" >/dev/null && cat "$tmp"; rm -f "$tmp"' > "$out_dir/Brewfile"
  run_as_user_capture "$MACBACK_PRIMARY_USER" env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 brew list --formula > "$out_dir/formulae.txt"
  run_as_user_capture "$MACBACK_PRIMARY_USER" env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 brew list --cask > "$out_dir/casks.txt"
  run_as_user_capture "$MACBACK_PRIMARY_USER" env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 brew leaves > "$out_dir/leaves.txt"
  run_as_user_capture "$MACBACK_PRIMARY_USER" env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 brew tap > "$out_dir/taps.txt"
  run_as_user_capture "$MACBACK_PRIMARY_USER" env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 brew services list > "$out_dir/services.txt" 2>/dev/null || true
}

write_permissions_inventory() {
  local rootfs_dir="$1"
  local out_file="$2"
  : > "$out_file"

  while IFS= read -r -d '' path; do
    local rel="${path#"$rootfs_dir"/}"
    local uid gid mode ftype target=""
    uid="$(stat -f '%u' "$path" 2>/dev/null || echo "")"
    gid="$(stat -f '%g' "$path" 2>/dev/null || echo "")"
    mode="$(stat -f '%p' "$path" 2>/dev/null || echo "")"
    ftype="$(stat -f '%HT' "$path" 2>/dev/null || echo "")"
    if [[ -L "$path" ]]; then
      target="$(readlink "$path" 2>/dev/null || true)"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$rel" "$ftype" "$uid" "$gid" "$mode" "$target" >> "$out_file"
  done < <(find "$rootfs_dir" -mindepth 1 -print0)
}

build_dynamic_excludes() {
  local run_dir="$1"
  local out_file="$2"
  : > "$out_file"
  {
    echo "/Volumes/**"
    echo "$run_dir/**"
    echo "$MACBACK_ROOT/output/**"
    echo "$MACBACK_ROOT/state/**"
  } >> "$out_file"
}

watch_destination_guard() {
  local guard_path="$1"
  local expected_uuid="$2"
  local expected_device_id="$3"
  local command_pid="$4"
  local failure_file="$5"

  while kill -0 "$command_pid" 2>/dev/null; do
    if ! destination_matches_guard "$guard_path" "$expected_uuid" "$expected_device_id"; then
      printf 'Destination volume disappeared or remounted: %s\n' "$guard_path" > "$failure_file"
      echo "Destination volume disappeared or remounted: $guard_path" >&2
      kill "$command_pid" 2>/dev/null || true
      return 0
    fi
    sleep 2
  done
}

run_with_destination_guard() {
  local target_path="$1"
  local failure_file="$2"
  shift 2

  rm -f "$failure_file"
  if ! destination_requires_mount_guard "$target_path"; then
    "$@"
    return $?
  fi

  local guard_path expected_uuid expected_device_id
  IFS=$'\t' read -r guard_path expected_uuid expected_device_id < <(destination_capture_guard "$target_path") || {
    echo "Destination is not a live mounted volume: $target_path" >&2
    return 75
  }

  "$@" &
  local command_pid=$!
  watch_destination_guard "$guard_path" "$expected_uuid" "$expected_device_id" "$command_pid" "$failure_file" &
  local watcher_pid=$!

  wait "$command_pid"
  local status=$?
  kill "$watcher_pid" 2>/dev/null || true
  wait "$watcher_pid" 2>/dev/null || true

  [[ -f "$failure_file" ]] && return 75
  return "$status"
}

pause_for_destination_change() {
  local destination_base="$1"
  local run_dir="$2"
  local expected_uuid="$3"

  while true; do
    echo
    section_header "Backup paused"
    kv "Reason" "Destination volume changed or disconnected"
    kv "Previous target" "$destination_base"

    local detected_root=""
    if [[ -n "$expected_uuid" ]]; then
      detected_root="$(find_destination_by_volume_uuid "$expected_uuid" 2>/dev/null || true)"
    fi

    if [[ -n "$detected_root" ]]; then
      local rebound_destination rebound_run_dir
      rebound_destination="$(destination_rebind_to_volume_root "$destination_base" "$detected_root")" || return 1
      rebound_run_dir="$(destination_rebind_to_volume_root "$run_dir" "$detected_root")" || return 1
      kv "Detected target" "$rebound_destination"
      kv "Detected run dir" "$rebound_run_dir"
      echo

      local choice
      choice="$(choose_from_lines "Destination changed" \
        "Continue on detected volume|Use $rebound_destination" \
        "Retry detection|Check again after reconnecting the drive" \
        "Stop here|Return to the menu and leave this run paused")" || return 1
      case "$choice" in
        Continue\ on\ detected\ volume)
          printf '%s\t%s\n' "$rebound_destination" "$rebound_run_dir"
          return 0
          ;;
        Retry\ detection) continue ;;
        Stop\ here) return 1 ;;
      esac
    else
      kv "Detected target" "not available"
      echo

      local choice
      choice="$(choose_from_lines "Destination changed" \
        "Retry detection|Check again after reconnecting the same drive" \
        "Stop here|Return to the menu and leave this run paused")" || return 1
      case "$choice" in
        Retry\ detection) continue ;;
        Stop\ here) return 1 ;;
      esac
    fi
  done
}

backup_files_component() {
  local run_dir="$1"
  local include_file="$2"
  local exclude_file="$3"
  local destination_guard_error="$4"
  local backup_mode="${5:-new}"
  local backup_speed_profile="${6:-normal}"
  local out_dir="$run_dir/components/files"
  local meta_dir="$run_dir/meta"
  local integrity_dir="$meta_dir/integrity"
  local rootfs_dir="$out_dir/rootfs"
  ensure_dir "$rootfs_dir"
  ensure_dir "$integrity_dir"

  local dynamic_excludes="$meta_dir/dynamic-excludes.txt"
  local filter_file="$meta_dir/rclone.filter"
  local rclone_flags=()
  build_dynamic_excludes "$run_dir" "$dynamic_excludes"
  generate_rclone_filter "$include_file" "$exclude_file" "$filter_file" "$dynamic_excludes"
  # Use in-place writes to avoid temp-file rename failures on external filesystems.
  rclone_flags+=(--filter-from "$filter_file" --links --progress --stats 2s --no-update-dir-modtime --inplace)
  while IFS= read -r flag; do
    [[ -n "$flag" ]] || continue
    rclone_flags+=("$flag")
  done < <(backup_speed_profile_copy_flags "$backup_speed_profile")
  if path_supports_metadata "$run_dir"; then
    rclone_flags+=(--metadata)
  else
    warn "Destination filesystem does not support POSIX-style metadata cleanly; relying on permissions inventory instead."
  fi

  local copy_status=0
  run_with_destination_guard "$run_dir" "$destination_guard_error" rclone copy / "$rootfs_dir" "${rclone_flags[@]}" || copy_status=$?
  if [[ "$copy_status" == "75" ]]; then
    return 75
  fi
  printf '%s\n' "$copy_status" > "$integrity_dir/rclone-copy.exit-code"

  write_permissions_inventory "$rootfs_dir" "$meta_dir/permissions.tsv"

  if [[ "$backup_mode" == "resume" ]]; then
    rm -f \
      "$integrity_dir/rclone-check.combined" \
      "$integrity_dir/rclone-check.differ" \
      "$integrity_dir/rclone-check.missing-on-dst" \
      "$integrity_dir/rclone-check.error"
    printf '%s\n' "$MACBACK_RCLONE_CHECK_SKIPPED_STATUS" > "$integrity_dir/rclone-check.exit-code"
    return 0
  fi

  local skipped_check_status=""
  skipped_check_status="$(backup_speed_profile_check_status "$backup_speed_profile" 2>/dev/null || true)"
  if [[ -n "$skipped_check_status" ]]; then
    rm -f \
      "$integrity_dir/rclone-check.combined" \
      "$integrity_dir/rclone-check.differ" \
      "$integrity_dir/rclone-check.missing-on-dst" \
      "$integrity_dir/rclone-check.error"
    printf '%s\n' "$skipped_check_status" > "$integrity_dir/rclone-check.exit-code"
    return 0
  fi

  local check_status=0
  run_with_destination_guard "$run_dir" "$destination_guard_error" \
    rclone check / "$rootfs_dir" \
    --filter-from "$filter_file" \
    --one-way \
    --combined "$integrity_dir/rclone-check.combined" \
    --differ "$integrity_dir/rclone-check.differ" \
    --missing-on-dst "$integrity_dir/rclone-check.missing-on-dst" \
    --error "$integrity_dir/rclone-check.error" || check_status=$?
  if [[ "$check_status" == "75" ]]; then
    return 75
  fi

  printf '%s\n' "$check_status" > "$integrity_dir/rclone-check.exit-code"
}

choose_component_flags() {
  local selected
  selected="$(choose_many_from_lines "Backup components" \
    "Files|Filesystem data and selected config paths" \
    "Homebrew|Package inventory and Brewfile" \
    "Keychain metadata|Keychain discovery and manual export guidance" \
    "Launchd metadata|User and custom launchd plists" \
    "System snapshot|System facts and app inventory reference")" || return 1
  local files="no" brew="no" keychain="no" launchd="no" system="no"
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      Files) files="yes" ;;
      Homebrew) brew="yes" ;;
      Keychain\ metadata) keychain="yes" ;;
      Launchd\ metadata) launchd="yes" ;;
      System\ snapshot) system="yes" ;;
    esac
  done <<< "$selected"
  printf '%s\t%s\t%s\t%s\t%s\n' "$files" "$brew" "$keychain" "$launchd" "$system"
}

choose_backup_speed_profile() {
  local choice
  choice="$(choose_from_lines "Backup speed" \
    "Normal|Safer defaults. Full rclone verification on new runs." \
    "Fast|Higher parallelism. Skip the long post-copy rclone check." \
    "Ultrafast|Highest parallelism. Skip full verification and compare by size only.")" || return 1

  case "$choice" in
    Normal) printf 'normal\n' ;;
    Fast) printf 'fast\n' ;;
    Ultrafast) printf 'ultrafast\n' ;;
    *) return 1 ;;
  esac
}

backup_speed_profile_label() {
  case "${1:-normal}" in
    normal) printf 'Normal\n' ;;
    fast) printf 'Fast\n' ;;
    ultrafast) printf 'Ultrafast\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

backup_speed_profile_copy_flags() {
  case "${1:-normal}" in
    normal)
      printf '%s\n' --transfers 4 --checkers 8
      ;;
    fast)
      printf '%s\n' --transfers 8 --checkers 16 --ignore-checksum
      ;;
    ultrafast)
      printf '%s\n' --transfers 16 --checkers 32 --ignore-checksum --size-only
      ;;
  esac
}

backup_speed_profile_check_status() {
  case "${1:-normal}" in
    fast) printf '%s\n' "$MACBACK_RCLONE_CHECK_SKIPPED_FAST_STATUS" ;;
    ultrafast) printf '%s\n' "$MACBACK_RCLONE_CHECK_SKIPPED_ULTRAFAST_STATUS" ;;
    *) return 1 ;;
  esac
}

edit_rules_loop() {
  local include_file="$1"
  local exclude_file="$2"
  while true; do
    section_header "Rules editor"
    kv "Includes" "$(count_non_comment_lines "$include_file")"
    kv "Excludes" "$(count_non_comment_lines "$exclude_file")"
    echo
    local choice
    choice="$(choose_from_lines "Rules editor" "Show includes" "Add include" "Remove include" "Show excludes" "Add exclude" "Remove exclude" "Continue")" || break
    case "$choice" in
      Show\ includes) nl -ba "$include_file" | sed -n "1,${MACBACK_MAX_PREVIEW_LINES}p" ;;
      Add\ include)
        prompt "Include path or pattern"
        local line
        ui_read_prompt_line
        line="$REPLY"
        [[ -n "$line" ]] && echo "$line" >> "$include_file"
        ;;
      Remove\ include)
        local include_options=()
        while IFS= read -r line || [[ -n "$line" ]]; do
          [[ -n "$line" ]] || continue
          include_options+=("$line")
        done < "$include_file"
        local kept_includes
        kept_includes="$(choose_many_from_lines "Select include rules to keep" "${include_options[@]}")" || true
        : > "$include_file"
        [[ -n "$kept_includes" ]] && printf '%s\n' "$kept_includes" > "$include_file"
        ;;
      Show\ excludes) nl -ba "$exclude_file" | sed -n "1,${MACBACK_MAX_PREVIEW_LINES}p" ;;
      Add\ exclude)
        prompt "Exclude pattern"
        local exclude_line
        ui_read_prompt_line
        exclude_line="$REPLY"
        [[ -n "$exclude_line" ]] && echo "$exclude_line" >> "$exclude_file"
        ;;
      Remove\ exclude)
        local exclude_options=()
        while IFS= read -r line || [[ -n "$line" ]]; do
          [[ -n "$line" ]] || continue
          exclude_options+=("$line")
        done < "$exclude_file"
        local kept_excludes
        kept_excludes="$(choose_many_from_lines "Select exclude rules to keep" "${exclude_options[@]}")" || true
        : > "$exclude_file"
        [[ -n "$kept_excludes" ]] && printf '%s\n' "$kept_excludes" > "$exclude_file"
        ;;
      Continue|"") break ;;
      *) warn "Invalid selection." ;;
    esac
    echo
  done
}

run_backup_flow() {
  require_root
  require_cmd rclone

  local destination_base
  destination_base="$(select_destination_base)" || return 1
  local backup_choice run_dir backup_mode
  backup_choice="$(choose_run_dir_for_backup "$destination_base")" || return 0
  IFS=$'\t' read -r backup_mode run_dir <<< "$backup_choice"
  local meta_dir="$run_dir/meta"
  local state_dir
  state_dir="$MACBACK_STATE_DIR/$(basename "$run_dir")"
  ensure_dir "$meta_dir"
  ensure_dir "$state_dir"

  local source_home="$MACBACK_PRIMARY_HOME"
  if [[ -f "$meta_dir/include-paths.txt" && -f "$meta_dir/exclude-patterns.txt" ]]; then
    cp "$meta_dir/include-paths.txt" "$state_dir/include-paths.txt"
    cp "$meta_dir/exclude-patterns.txt" "$state_dir/exclude-patterns.txt"
  else
    seed_effective_rules "$state_dir" "$source_home"
  fi

  local component_flags
  component_flags="$(choose_component_flags)" || return 0
  local files_enabled brew_enabled keychain_enabled launchd_enabled system_enabled
  IFS=$'\t' read -r files_enabled brew_enabled keychain_enabled launchd_enabled system_enabled <<< "$component_flags"
  local backup_speed_profile
  backup_speed_profile="$(choose_backup_speed_profile)" || return 0
  edit_rules_loop "$state_dir/include-paths.txt" "$state_dir/exclude-patterns.txt"

  cp "$state_dir/include-paths.txt" "$meta_dir/include-paths.txt"
  cp "$state_dir/exclude-patterns.txt" "$meta_dir/exclude-patterns.txt"

  section_header "Backup summary"
  kv "Destination" "$destination_base"
  kv "Run dir" "$run_dir"
  kv "Files" "$files_enabled"
  kv "Homebrew" "$brew_enabled"
  kv "Keychain metadata" "$keychain_enabled"
  kv "Launchd metadata" "$launchd_enabled"
  kv "System snapshot" "$system_enabled"
  kv "Speed mode" "$(backup_speed_profile_label "$backup_speed_profile")"
  kv "Include rules" "$(count_non_comment_lines "$meta_dir/include-paths.txt")"
  kv "Exclude rules" "$(count_non_comment_lines "$meta_dir/exclude-patterns.txt")"
  echo
  if ! confirm "Start backup now?"; then
    warn "Backup cancelled."
    return 0
  fi
  destination_assert_write_target "$run_dir" || return 1

  local destination_guard_uuid=""
  if destination_requires_mount_guard "$run_dir"; then
    local destination_guard_info=""
    destination_guard_info="$(destination_capture_guard "$run_dir")" || return 1
    IFS=$'\t' read -r _ destination_guard_uuid _ <<< "$destination_guard_info"
  fi

  local created_at started_at finished_at status
  created_at="$(timestamp_utc)"
  started_at="$created_at"
  finished_at=""
  status="running"
  printf '%s\n' "$$" > "$meta_dir/active.pid"

  write_run_env "$meta_dir/run.env" \
    SPEC_VERSION "$MACBACK_SPEC_VERSION" \
    TOOL_VERSION "$MACBACK_TOOL_VERSION" \
    CREATED_AT "$created_at" \
    STARTED_AT "$started_at" \
    STATUS "$status" \
    DESTINATION_BASE "$destination_base" \
    RUN_DIR "$run_dir" \
    SOURCE_USER "$MACBACK_PRIMARY_USER" \
    SOURCE_HOME "$source_home" \
    BACKUP_PROFILE "$backup_speed_profile" \
    SOURCE_SERIAL "$MACBACK_MACHINE_SERIAL"
  write_run_json "$meta_dir/run.json" "$created_at" "$started_at" "$finished_at" "$status" "$destination_base" "$run_dir" "$MACBACK_PRIMARY_USER" "$source_home" "$MACBACK_MACHINE_SERIAL"

  [[ "$system_enabled" == "yes" ]] && backup_system_snapshot "$run_dir"
  [[ "$launchd_enabled" == "yes" ]] && backup_launchd_metadata "$run_dir"
  [[ "$keychain_enabled" == "yes" ]] && backup_keychain_metadata "$run_dir"
  if [[ "$brew_enabled" == "yes" ]]; then
    if ! backup_homebrew_component "$run_dir"; then
      status="completed_with_warnings"
    fi
  fi
  if [[ "$files_enabled" == "yes" ]]; then
    local destination_guard_error="$state_dir/destination-guard.error"
    while true; do
      backup_files_component "$run_dir" "$meta_dir/include-paths.txt" "$meta_dir/exclude-patterns.txt" "$destination_guard_error" "$backup_mode" "$backup_speed_profile"
      local files_status=$?
      if [[ "$files_status" == "0" ]]; then
        break
      fi
      if [[ "$files_status" != "75" ]]; then
        break
      fi

      local rebound_paths
      rebound_paths="$(pause_for_destination_change "$destination_base" "$run_dir" "$destination_guard_uuid")" || {
        warn "Backup paused. Reconnect the destination and use Resume latest run to continue."
        return 1
      }
      IFS=$'\t' read -r destination_base run_dir <<< "$rebound_paths"
      meta_dir="$run_dir/meta"
      destination_assert_write_target "$run_dir" || return 1
      if destination_requires_mount_guard "$run_dir"; then
        local destination_guard_info=""
        destination_guard_info="$(destination_capture_guard "$run_dir")" || return 1
        IFS=$'\t' read -r _ destination_guard_uuid _ <<< "$destination_guard_info"
      fi
    done
  fi

  if ! destination_assert_write_target "$run_dir"; then
    if [[ -n "$destination_guard_uuid" ]]; then
      local rebound_paths
      rebound_paths="$(pause_for_destination_change "$destination_base" "$run_dir" "$destination_guard_uuid")" || {
        warn "Backup paused. Reconnect the destination and use Resume latest run to continue."
        return 1
      }
      IFS=$'\t' read -r destination_base run_dir <<< "$rebound_paths"
      meta_dir="$run_dir/meta"
      destination_assert_write_target "$run_dir" || return 1
      if destination_requires_mount_guard "$run_dir"; then
        local destination_guard_info=""
        destination_guard_info="$(destination_capture_guard "$run_dir")" || return 1
        IFS=$'\t' read -r _ destination_guard_uuid _ <<< "$destination_guard_info"
      fi
    else
      return 1
    fi
  fi

  finished_at="$(timestamp_utc)"
  status="completed"
  local copy_exit="" check_exit=""
  if [[ -f "$meta_dir/integrity/rclone-copy.exit-code" ]]; then
    copy_exit="$(cat "$meta_dir/integrity/rclone-copy.exit-code")"
  fi
  if [[ -f "$meta_dir/integrity/rclone-check.exit-code" ]]; then
    check_exit="$(cat "$meta_dir/integrity/rclone-check.exit-code")"
  fi
  if [[ "$copy_exit" != "0" && -n "$copy_exit" ]] || [[ "$check_exit" != "0" && -n "$check_exit" ]]; then
    if ! rclone_check_status_is_skipped "$check_exit"; then
      status="completed_with_warnings"
    fi
  fi
  write_run_env "$meta_dir/run.env" \
    SPEC_VERSION "$MACBACK_SPEC_VERSION" \
    TOOL_VERSION "$MACBACK_TOOL_VERSION" \
    CREATED_AT "$created_at" \
    STARTED_AT "$started_at" \
    FINISHED_AT "$finished_at" \
    STATUS "$status" \
    DESTINATION_BASE "$destination_base" \
    RUN_DIR "$run_dir" \
    SOURCE_USER "$MACBACK_PRIMARY_USER" \
    SOURCE_HOME "$source_home" \
    BACKUP_PROFILE "$backup_speed_profile" \
    SOURCE_SERIAL "$MACBACK_MACHINE_SERIAL"
  write_run_json "$meta_dir/run.json" "$created_at" "$started_at" "$finished_at" "$status" "$destination_base" "$run_dir" "$MACBACK_PRIMARY_USER" "$source_home" "$MACBACK_MACHINE_SERIAL"
  write_manifest_json "$meta_dir/manifest.json" "$run_dir" "$([[ "$files_enabled" == "yes" ]] && echo true || echo false)" "$([[ "$brew_enabled" == "yes" ]] && echo true || echo false)" "$([[ "$keychain_enabled" == "yes" ]] && echo true || echo false)" "$([[ "$system_enabled" == "yes" ]] && echo true || echo false)" "$([[ "$launchd_enabled" == "yes" ]] && echo true || echo false)" "remap_to_target_home" "preserve_system_remap_user"
  write_integrity_checksums "$meta_dir/integrity" "$meta_dir/run.json" "$meta_dir/manifest.json" "$meta_dir/include-paths.txt" "$meta_dir/exclude-patterns.txt" "$meta_dir/permissions.tsv"
  rm -f "$meta_dir/active.pid"

  echo
  section_header "Backup result"
  kv "Run dir" "$run_dir"
  kv "Started" "$started_at"
  kv "Finished" "$finished_at"
  if [[ "$files_enabled" == "yes" ]]; then
    if [[ -n "$copy_exit" ]]; then
      if [[ "$copy_exit" == "0" ]]; then
        kv "rclone copy" "${C_OK}OK${C_RESET}"
      else
        kv "rclone copy" "${C_ERROR}FAILED (exit $copy_exit)${C_RESET}"
      fi
    fi
    if [[ -n "$check_exit" ]]; then
      if [[ "$check_exit" == "0" ]]; then
        kv "rclone check" "${C_OK}OK${C_RESET}"
      elif rclone_check_status_is_skipped "$check_exit"; then
        kv "rclone check" "${C_DIM}$(rclone_check_status_label "$check_exit")${C_RESET}"
      else
        kv "rclone check" "${C_WARN}WARNINGS (exit $check_exit)${C_RESET}"
        if [[ -f "$meta_dir/integrity/rclone-check.differ" ]]; then
          local differ_count
          differ_count="$(wc -l < "$meta_dir/integrity/rclone-check.differ" | tr -d ' ')"
          [[ "$differ_count" != "0" ]] && kv "  Differing" "$differ_count files"
        fi
        if [[ -f "$meta_dir/integrity/rclone-check.missing-on-dst" ]]; then
          local missing_count
          missing_count="$(wc -l < "$meta_dir/integrity/rclone-check.missing-on-dst" | tr -d ' ')"
          [[ "$missing_count" != "0" ]] && kv "  Missing" "$missing_count files"
        fi
        if [[ -f "$meta_dir/integrity/rclone-check.error" ]]; then
          local error_count
          error_count="$(wc -l < "$meta_dir/integrity/rclone-check.error" | tr -d ' ')"
          [[ "$error_count" != "0" ]] && kv "  Errors" "$error_count files"
        fi
      fi
    fi
  fi
  echo
  case "$status" in
    completed)
      success "Backup completed successfully." ;;
    completed_with_warnings)
      warn "Backup completed with warnings. Review integrity files in: $meta_dir/integrity/" ;;
    *)
      error "Backup ended with status: $status" ;;
  esac
}
