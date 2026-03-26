#!/usr/bin/env bash

select_target_user() {
  local users=()
  local user
  while IFS= read -r user; do
    users+=("$user")
  done < <(detect_target_users)
  users+=("Back")
  choose_from_lines "Restore target user" "${users[@]}"
}

show_homebrew_install_guidance() {
  local target_user="$1"
  box \
    "Homebrew is not installed on this Mac." \
    "This backup contains Homebrew data." \
    "" \
    "Suggested next step:" \
    "Run the official installer as the target user:" \
    "sudo -u $target_user /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
}

select_backup_components() {
  local has_files="$1"
  local has_brew="$2"
  local has_keychain="$3"
  local options=()
  [[ "$has_files" == "yes" ]] && options+=("Files|Restore files, configs, and permissions")
  [[ "$has_brew" == "yes" ]] && options+=("Homebrew|Replay backed-up Homebrew selections")
  [[ "$has_keychain" == "yes" ]] && options+=("Keychain guidance|Show keychain metadata and manual steps")
  local selected
  selected="$(choose_many_from_lines "Restore components" "${options[@]}")" || return 1
  local files="no" brew="no" keychain="no"
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      Files) files="yes" ;;
      Homebrew) brew="yes" ;;
      Keychain\ guidance) keychain="yes" ;;
    esac
  done <<< "$selected"
  printf '%s\t%s\t%s\n' "$files" "$brew" "$keychain"
}

select_restore_rules() {
  local include_file="$1"
  local selected_file="$2"
  local options=()
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    options+=("$line")
  done < "$include_file"
  local selected
  selected="$(choose_many_from_lines "File restore selection" "${options[@]}")" || return 1
  : > "$selected_file"
  [[ -n "$selected" ]] && printf '%s\n' "$selected" > "$selected_file"
}

discover_user_restore_candidates() {
  local user_root="$1"
  local out_file="$2"
  : > "$out_file"

  if [[ -d "$user_root/Library/Preferences" ]]; then
    find "$user_root/Library/Preferences" -mindepth 1 -maxdepth 1 -type f 2>/dev/null \
      | sed "s#^$user_root##" \
      | sort >> "$out_file"
  fi

  if [[ -d "$user_root/Library/Application Support" ]]; then
    find "$user_root/Library/Application Support" -mindepth 1 -maxdepth 1 2>/dev/null \
      | sed "s#^$user_root##" \
      | sed 's#$#/**#' \
      | sort >> "$out_file"
  fi

  if [[ -d "$user_root/.config" ]]; then
    find "$user_root/.config" -mindepth 1 -maxdepth 1 2>/dev/null \
      | sed "s#^$user_root##" \
      | sed 's#$#/**#' \
      | sort >> "$out_file"
  fi

  if [[ -d "$user_root/Library/LaunchAgents" ]]; then
    find "$user_root/Library/LaunchAgents" -mindepth 1 -maxdepth 1 -type f 2>/dev/null \
      | sed "s#^$user_root##" \
      | sort >> "$out_file"
  fi

  awk '!seen[$0]++' "$out_file" > "$out_file.tmp"
  mv "$out_file.tmp" "$out_file"
}

select_granular_restore_excludes() {
  local candidates_file="$1"
  local extra_excludes_file="$2"
  : > "$extra_excludes_file"
  [[ -s "$candidates_file" ]] || return 0

  local options=()
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    options+=("$line")
  done < "$candidates_file"

  local all_items selected_items
  all_items="$(cat "$candidates_file")"
  selected_items="$(choose_many_from_lines "Granular app-config restore" "${options[@]}")" || return 1
  : > "$candidates_file"
  : > "$extra_excludes_file"
  [[ -n "$selected_items" ]] && printf '%s\n' "$selected_items" > "$candidates_file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    if ! grep -F -x -- "$line" "$candidates_file" >/dev/null 2>&1; then
      printf '%s\n' "$line" >> "$extra_excludes_file"
    fi
  done <<< "$all_items"
}

build_restore_filters() {
  local selected_include="$1"
  local exclude_file="$2"
  local source_home="$3"
  local _target_home="$4"
  local system_include="$5"
  local user_include="$6"
  local extra_user_excludes_file="${7:-}"
  : > "$system_include"
  : > "$user_include"

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    if [[ "$line" == "$source_home"* ]]; then
      local stripped="${line#"$source_home"}"
      [[ -n "$stripped" ]] || stripped="/"
      printf '%s\n' "$stripped" >> "$user_include"
    else
      printf '%s\n' "$line" >> "$system_include"
    fi
  done < "$selected_include"

  # Preserve excludes as-is for system restore; for user restore remap source home to target home.
  local system_exclude="$system_include.exclude"
  local user_exclude="$user_include.exclude"
  cp "$exclude_file" "$system_exclude"
  awk -v src="$source_home" '
    {
      if ($0 ~ "^" src) sub("^" src, "", $0)
      if ($0 == "") $0 = "/"
      print
    }
  ' "$exclude_file" > "$user_exclude"
  if [[ -n "$extra_user_excludes_file" && -f "$extra_user_excludes_file" ]]; then
    cat "$extra_user_excludes_file" >> "$user_exclude"
    awk '!seen[$0]++' "$user_exclude" > "$user_exclude.tmp"
    mv "$user_exclude.tmp" "$user_exclude"
  fi

  generate_rclone_filter "$system_include" "$system_exclude" "$system_include.filter"
  generate_rclone_filter "$user_include" "$user_exclude" "$user_include.filter"
}

restore_files_component() {
  local run_dir="$1"
  local target_user="$2"
  local target_home="$3"
  local source_home="$4"

  local meta_dir="$run_dir/meta"
  local rootfs="$run_dir/components/files/rootfs"
  local source_home_root="$rootfs$source_home"
  local selected_include="$meta_dir/restore-include-paths.txt"
  select_restore_rules "$meta_dir/include-paths.txt" "$selected_include"

  local system_include="$meta_dir/restore-system-include.txt"
  local user_include="$meta_dir/restore-user-include.txt"
  local candidate_file="$meta_dir/restore-user-candidates.txt"
  local extra_user_excludes="$meta_dir/restore-user-extra-excludes.txt"
  discover_user_restore_candidates "$source_home_root" "$candidate_file"
  select_granular_restore_excludes "$candidate_file" "$extra_user_excludes"
  build_restore_filters "$selected_include" "$meta_dir/exclude-patterns.txt" "$source_home" "$target_home" "$system_include" "$user_include" "$extra_user_excludes"

  section_header "Restore preview"
  kv "Source rootfs" "$rootfs"
  kv "System restore target" "/"
  kv "User restore target" "$target_home"
  if ! confirm "Run file restore preview first?"; then
    warn "Skipping preview."
  else
    if [[ -s "$system_include.filter" ]]; then
      rclone copy "$rootfs" / --filter-from "$system_include.filter" --links --metadata --dry-run
    fi
    if [[ -s "$user_include.filter" ]]; then
      rclone copy "$source_home_root" "$target_home" --filter-from "$user_include.filter" --links --metadata --dry-run
    fi
  fi

  if ! confirm "Run file restore now?"; then
    warn "File restore cancelled."
    return 0
  fi

  if [[ -s "$system_include.filter" ]]; then
    rclone copy "$rootfs" / --filter-from "$system_include.filter" --links --metadata --progress --check-first
  fi
  if [[ -s "$user_include.filter" ]]; then
    rclone copy "$source_home_root" "$target_home" --filter-from "$user_include.filter" --links --metadata --progress --check-first
  fi

  reconcile_permissions "$run_dir" "$target_user" "$target_home" "$source_home"
}

reconcile_permissions() {
  local run_dir="$1"
  local target_user="$2"
  local target_home="$3"
  local source_home="$4"
  local perms_file="$run_dir/meta/permissions.tsv"
  [[ -f "$perms_file" ]] || return 0
  local errors_file="$run_dir/meta/restore-permissions.errors"
  : > "$errors_file"

  local target_uid target_gid
  target_uid="$(id -u "$target_user")"
  target_gid="$(id -g "$target_user")"

  while IFS=$'\t' read -r rel _ftype uid gid mode _target || [[ -n "$rel" ]]; do
    local dest_path="/$rel"
    local chmod_mode="$mode"
    chmod_mode="${chmod_mode: -4}"
    if [[ "$dest_path" == "$source_home"* ]]; then
      dest_path="$target_home${dest_path#"$source_home"}"
      if [[ -L "$dest_path" ]]; then
        chown -h "$target_uid:$target_gid" "$dest_path" 2>/dev/null || echo "chown -h failed: $dest_path" >> "$errors_file"
      elif [[ -e "$dest_path" ]]; then
        chown "$target_uid:$target_gid" "$dest_path" 2>/dev/null || echo "chown failed: $dest_path" >> "$errors_file"
        chmod "$chmod_mode" "$dest_path" 2>/dev/null || echo "chmod failed: $dest_path" >> "$errors_file"
      fi
    else
      if [[ -L "$dest_path" ]]; then
        chown -h "$uid:$gid" "$dest_path" 2>/dev/null || echo "chown -h failed: $dest_path" >> "$errors_file"
      elif [[ -e "$dest_path" ]]; then
        chown "$uid:$gid" "$dest_path" 2>/dev/null || echo "chown failed: $dest_path" >> "$errors_file"
        chmod "$chmod_mode" "$dest_path" 2>/dev/null || echo "chmod failed: $dest_path" >> "$errors_file"
      fi
    fi
  done < "$perms_file"

  if [[ ! -s "$errors_file" ]]; then
    rm -f "$errors_file"
  else
    warn "Permission reconciliation reported issues. See $errors_file"
  fi
}

build_brew_restore_selection() {
  local formulas_file="$1"
  local casks_file="$2"
  local selected_file="$3"
  : > "$selected_file"
  [[ -f "$formulas_file" ]] && awk 'NF {print "brew\t" $0}' "$formulas_file" >> "$selected_file"
  [[ -f "$casks_file" ]] && awk 'NF {print "cask\t" $0}' "$casks_file" >> "$selected_file"
}

choose_brew_restore_items() {
  local selected_file="$1"
  [[ -s "$selected_file" ]] || return 0
  local options=()
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    options+=("${line%%$'\t'*}: ${line#*$'\t'}")
  done < "$selected_file"
  local selected
  selected="$(choose_many_from_lines "Homebrew restore selection" "${options[@]}")" || return 1
  local selected_display_file
  selected_display_file="$(mktemp)"
  : > "$selected_display_file"
  [[ -n "$selected" ]] && printf '%s\n' "$selected" > "$selected_display_file"
  local original="$selected_file.original"
  cp "$selected_file" "$original"
  : > "$selected_file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    local display="${line%%$'\t'*}: ${line#*$'\t'}"
    grep -F -x -- "$display" "$selected_display_file" >/dev/null 2>&1 && printf '%s\n' "$line" >> "$selected_file"
  done < "$original"
  rm -f "$selected_display_file" "$original"
}

restore_brew_component() {
  local run_dir="$1"
  local brew_dir="$run_dir/components/brew"
  local brewfile="$brew_dir/Brewfile"
  local formulas="$brew_dir/formulae.txt"
  local casks="$brew_dir/casks.txt"

  [[ -f "$brewfile" ]] || { warn "No Brewfile found in backup."; return 1; }

  if ! has_cmd brew; then
    show_homebrew_install_guidance "$RESTORE_TARGET_USER"
    if ! is_tty; then
      warn "Homebrew missing in non-interactive mode; skipping brew restore."
      return 2
    fi
    prompt "Press Enter after Homebrew is installed, or Ctrl-C to stop"
    ui_read_prompt_line
    if ! has_cmd brew; then
      warn "Homebrew is still not installed. Skipping brew restore."
      return 0
    fi
  fi

  section_header "Homebrew restore"
  kv "Formulae file" "$formulas"
  kv "Casks file" "$casks"
  box \
    "Default mode is restore all Homebrew items." \
    "You can deselect packages before replay."

  local temp_brewfile
  temp_brewfile="$(mktemp)"
  grep '^tap ' "$brewfile" > "$temp_brewfile" || true
  local selection_file
  selection_file="$(mktemp)"
  build_brew_restore_selection "$formulas" "$casks" "$selection_file"
  choose_brew_restore_items "$selection_file"
  if [[ ! -s "$selection_file" ]]; then
    warn "No Homebrew items selected."
    rm -f "$selection_file" "$temp_brewfile"
    return 0
  fi
  while IFS=$'\t' read -r item_type item_name || [[ -n "$item_type" ]]; do
    grep -E "^${item_type} \"${item_name}\"$" "$brewfile" >> "$temp_brewfile" || warn "Not found in Brewfile: $item_name"
  done < "$selection_file"
  rm -f "$selection_file"

  sort -u "$temp_brewfile" -o "$temp_brewfile"
  if ! grep -Eq '^(brew|cask) "' "$temp_brewfile"; then
    warn "Subset Brewfile contains no formulae or casks."
    rm -f "$temp_brewfile"
    return 0
  fi
  kv "Selected items" "$(grep -Ec '^(brew|cask) "' "$temp_brewfile")"
  box "Generated subset Brewfile:" "$temp_brewfile"
  if confirm "Run brew bundle with this subset Brewfile?"; then
    chmod 644 "$temp_brewfile"
    run_as_user_capture "$RESTORE_TARGET_USER" env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 brew bundle --file "$temp_brewfile"
  else
    warn "Brew restore cancelled."
  fi
}

run_inspect_flow() {
  local input="${1:-}"
  local run_dir="" manifest=""

  if [[ -z "$input" ]]; then
    input="$(select_backup_run_dir)" || return 1
  fi

  if [[ -d "$input" ]]; then
    run_dir="$input"
    [[ -f "$run_dir/meta/manifest.json" ]] && manifest="$run_dir/meta/manifest.json"
  elif [[ -f "$input" ]]; then
    manifest="$input"
    run_dir="$(dirname "$(dirname "$manifest")")"
  else
    error "Not found: $input"
    return 1
  fi

  local meta_dir="$run_dir/meta"
  [[ -d "$meta_dir" ]] || { error "No meta directory in: $run_dir"; return 1; }
  [[ -f "$meta_dir/run.env" ]] && load_run_env "$meta_dir/run.env"

  print_banner "Backup inspection"
  kv "Run dir" "$run_dir"
  [[ -n "${CREATED_AT:-}" ]] && kv "Created" "$CREATED_AT"
  [[ -n "${FINISHED_AT:-}" ]] && kv "Finished" "${FINISHED_AT:-pending}"
  [[ -n "${STATUS:-}" ]] && kv "Status" "$STATUS"
  if [[ -n "${SOURCE_SERIAL:-}" && -n "${MACBACK_MACHINE_SERIAL:-}" && "$SOURCE_SERIAL" == "$MACBACK_MACHINE_SERIAL" ]]; then
    kv "Serial" "${C_DIM}matches this Mac${C_RESET}"
  fi
  if [[ -n "$manifest" ]]; then
    kv "Manifest" "${C_OK}present${C_RESET}"
  else
    kv "Manifest" "${C_WARN}MISSING (backup incomplete)${C_RESET}"
  fi
  [[ -f "$meta_dir/include-paths.txt" ]] && kv "Includes" "$(count_non_comment_lines "$meta_dir/include-paths.txt")"
  [[ -f "$meta_dir/exclude-patterns.txt" ]] && kv "Excludes" "$(count_non_comment_lines "$meta_dir/exclude-patterns.txt")"
  kv "Files" "$( [[ -d "$run_dir/components/files/rootfs" ]] && echo yes || echo no )"
  kv "Brew" "$( [[ -d "$run_dir/components/brew" ]] && echo yes || echo no )"
  kv "Keychain" "$( [[ -d "$run_dir/components/keychain" ]] && echo yes || echo no )"
  if [[ -f "$run_dir/components/system/applications.txt" ]]; then
    kv "Applications ref" "$(wc -l < "$run_dir/components/system/applications.txt" | tr -d ' ') listed"
  fi
  if [[ -n "$manifest" ]]; then
    case "$(verify_manifest_checksums "$manifest"; echo $?)" in
      0) kv "Integrity" "manifest checksums OK" ;;
      2) kv "Integrity" "checksum file missing" ;;
      *) kv "Integrity" "checksum verification failed" ;;
    esac
    case "$(read_files_verification_status "$manifest" 2>/dev/null || echo missing)" in
      0) kv "Files verify" "rclone check OK" ;;
      "$MACBACK_RCLONE_CHECK_SKIPPED_STATUS") kv "Files verify" "skipped for fast resume" ;;
      2|missing) kv "Files verify" "status missing" ;;
      *) kv "Files verify" "rclone check reported issues" ;;
    esac
  else
    if [[ -f "$meta_dir/integrity/rclone-copy.exit-code" ]]; then
      local copy_exit
      copy_exit="$(cat "$meta_dir/integrity/rclone-copy.exit-code")"
      [[ "$copy_exit" == "0" ]] && kv "rclone copy" "${C_OK}OK${C_RESET}" || kv "rclone copy" "${C_ERROR}FAILED (exit $copy_exit)${C_RESET}"
    fi
    if [[ -f "$meta_dir/integrity/rclone-check.exit-code" ]]; then
      local check_exit
      check_exit="$(cat "$meta_dir/integrity/rclone-check.exit-code")"
      if [[ "$check_exit" == "0" ]]; then
        kv "Files verify" "rclone check OK"
      elif rclone_check_status_is_skipped "$check_exit"; then
        kv "Files verify" "skipped for fast resume"
      else
        kv "Files verify" "rclone check reported issues"
      fi
    fi
  fi
}

run_restore_flow() {
  require_root
  require_cmd rclone

  local manifest="${1:-}"
  if [[ -z "$manifest" ]]; then
    manifest="$(select_backup_manifest)" || return 1
  fi
  validate_backup_manifest "$manifest" || { error "Invalid backup manifest: $manifest"; return 1; }
  local run_dir
  run_dir="$(dirname "$(dirname "$manifest")")"
  local meta_dir="$run_dir/meta"
  load_run_env "$meta_dir/run.env"

  BACKUP_SOURCE_USER="$SOURCE_USER"
  local source_home="${SOURCE_HOME:-}"
  [[ -n "$source_home" ]] || { error "Backup metadata is missing SOURCE_HOME."; return 1; }
  if [[ -n "${SOURCE_SERIAL:-}" && -n "${MACBACK_MACHINE_SERIAL:-}" && "$SOURCE_SERIAL" == "$MACBACK_MACHINE_SERIAL" ]]; then
    kv "Serial" "${C_DIM}matches this Mac${C_RESET}"
  fi
  RESTORE_TARGET_USER="$(select_target_user)" || return 1
  [[ "$RESTORE_TARGET_USER" != "Back" ]] || return 0
  local target_home
  target_home="$(detect_primary_home "$RESTORE_TARGET_USER")"

  if [[ "$RESTORE_TARGET_USER" != "$BACKUP_SOURCE_USER" ]]; then
    box \
      "Restore user differs from backup source user." \
      "Source user: $BACKUP_SOURCE_USER" \
      "Target user: $RESTORE_TARGET_USER" \
      "Home-directory paths will be remapped to $target_home"
  fi

  local restore_components
  restore_components="$(select_backup_components "$([[ -d "$run_dir/components/files/rootfs" ]] && echo yes || echo no)" "$([[ -d "$run_dir/components/brew" ]] && echo yes || echo no)" "$([[ -d "$run_dir/components/keychain" ]] && echo yes || echo no)")" || return 0
  local files_enabled brew_enabled keychain_enabled
  IFS=$'\t' read -r files_enabled brew_enabled keychain_enabled <<< "$restore_components"

  case "$(read_files_verification_status "$manifest" 2>/dev/null || echo missing)" in
    0|"") ;;
    "$MACBACK_RCLONE_CHECK_SKIPPED_STATUS") ;;
    *)
      warn "This backup recorded file verification issues."
      if ! confirm "Continue with restore anyway?"; then
        warn "Restore cancelled."
        return 0
      fi
      ;;
  esac

  if [[ "$brew_enabled" == "yes" ]] && ! has_cmd brew; then
    show_homebrew_install_guidance "$RESTORE_TARGET_USER"
  fi

  [[ "$files_enabled" == "yes" ]] && restore_files_component "$run_dir" "$RESTORE_TARGET_USER" "$target_home" "$source_home"
  [[ "$brew_enabled" == "yes" ]] && restore_brew_component "$run_dir"
  if [[ "$keychain_enabled" == "yes" ]]; then
    section_header "Keychain guidance"
    box "Keychain restore is manual in v1." "Review the files in $run_dir/components/keychain."
  fi
}

run_doctor_flow() {
  local run_dir="${1:-}"
  if [[ -z "$run_dir" ]]; then
    run_dir="$(select_backup_run_dir)" || return 1
  fi
  [[ -d "$run_dir" ]] || { error "Directory not found: $run_dir"; return 1; }

  local meta_dir="$run_dir/meta"
  local issues=0

  print_banner "Backup doctor"
  kv "Run dir" "$run_dir"
  echo

  # --- Permission checks ---
  section_header "Permissions"

  local volume_root
  volume_root="$(printf '%s' "$run_dir" | sed 's#\(/Volumes/[^/]*\).*#\1#')"
  if [[ "$volume_root" == /Volumes/* && -d "$volume_root" ]]; then
    if sudo -u "$MACBACK_PRIMARY_USER" ls "$volume_root" >/dev/null 2>&1; then
      kv "Volume root" "${C_OK}readable by $MACBACK_PRIMARY_USER${C_RESET}"
    else
      local vol_perms
      vol_perms="$(stat -f '%Sp' "$volume_root" 2>/dev/null || echo "?")"
      kv "Volume root" "${C_ERROR}not readable by $MACBACK_PRIMARY_USER ($vol_perms)${C_RESET}"
      issues=$((issues + 1))
      if confirm "Fix? (chmod o+rX $volume_root)"; then
        chmod o+rX "$volume_root"
        kv "Volume root" "${C_OK}fixed${C_RESET}"
        issues=$((issues - 1))
      fi
    fi
  fi

  local backup_root
  backup_root="$(printf '%s' "$run_dir" | sed 's#\(/macback\).*#\1#')"
  backup_root="${volume_root}${backup_root##*"$volume_root"}"
  if [[ -d "$backup_root" ]]; then
    local bad_count
    bad_count="$(find "$backup_root" -type d ! -perm -o=rx 2>/dev/null | wc -l | tr -d ' ')"
    if (( bad_count > 0 )); then
      kv "Backup dirs" "${C_ERROR}$bad_count dir(s) not readable by others${C_RESET}"
      issues=$((issues + 1))
      if confirm "Fix? (chmod o+rX on all dirs under $backup_root)"; then
        find "$backup_root" -type d -exec chmod o+rX {} +
        kv "Backup dirs" "${C_OK}fixed${C_RESET}"
        issues=$((issues - 1))
      fi
    else
      kv "Backup dirs" "${C_OK}OK${C_RESET}"
    fi

    local bad_files
    bad_files="$(find "$backup_root/meta" "$backup_root/components" -type f ! -perm -o=r 2>/dev/null | wc -l | tr -d ' ')"
    if (( bad_files > 0 )); then
      kv "Backup files" "${C_ERROR}$bad_files file(s) not readable by others${C_RESET}"
      issues=$((issues + 1))
      if confirm "Fix? (chmod o+r on files under $backup_root)"; then
        find "$backup_root" -type f -exec chmod o+r {} +
        kv "Backup files" "${C_OK}fixed${C_RESET}"
        issues=$((issues - 1))
      fi
    else
      kv "Backup files" "${C_OK}OK${C_RESET}"
    fi
  fi

  echo
  # --- Metadata checks ---
  section_header "Metadata"

  if [[ -f "$meta_dir/run.env" ]]; then
    kv "run.env" "${C_OK}OK${C_RESET}"
  else
    kv "run.env" "${C_ERROR}MISSING${C_RESET}"
    issues=$((issues + 1))
  fi

  if [[ -f "$meta_dir/run.json" ]]; then
    kv "run.json" "${C_OK}OK${C_RESET}"
  else
    kv "run.json" "${C_ERROR}MISSING${C_RESET}"
    issues=$((issues + 1))
  fi

  if [[ -f "$meta_dir/manifest.json" ]]; then
    kv "manifest.json" "${C_OK}OK${C_RESET}"
  else
    kv "manifest.json" "${C_WARN}MISSING (backup may be incomplete)${C_RESET}"
    issues=$((issues + 1))
  fi

  echo
  # --- Integrity checks ---
  section_header "Integrity"

  if [[ -f "$meta_dir/integrity/rclone-copy.exit-code" ]]; then
    local copy_exit
    copy_exit="$(cat "$meta_dir/integrity/rclone-copy.exit-code")"
    if [[ "$copy_exit" == "0" ]]; then
      kv "rclone copy" "${C_OK}OK${C_RESET}"
    else
      kv "rclone copy" "${C_ERROR}FAILED (exit $copy_exit)${C_RESET}"
      issues=$((issues + 1))
    fi
  else
    kv "rclone copy" "${C_DIM}not recorded${C_RESET}"
  fi

  if [[ -f "$meta_dir/integrity/rclone-check.exit-code" ]]; then
    local check_exit
    check_exit="$(cat "$meta_dir/integrity/rclone-check.exit-code")"
    if [[ "$check_exit" == "0" ]]; then
      kv "rclone check" "${C_OK}OK${C_RESET}"
    elif rclone_check_status_is_skipped "$check_exit"; then
      kv "rclone check" "${C_DIM}skipped for fast resume${C_RESET}"
    else
      kv "rclone check" "${C_WARN}WARNINGS (exit $check_exit)${C_RESET}"
      issues=$((issues + 1))
    fi
  else
    kv "rclone check" "${C_DIM}not recorded${C_RESET}"
  fi

  if [[ -f "$meta_dir/manifest.json" ]]; then
    case "$(verify_manifest_checksums "$meta_dir/manifest.json"; echo $?)" in
      0) kv "Checksums" "${C_OK}OK${C_RESET}" ;;
      2) kv "Checksums" "${C_DIM}checksum file missing${C_RESET}" ;;
      *) kv "Checksums" "${C_ERROR}verification failed${C_RESET}"; issues=$((issues + 1)) ;;
    esac
  fi

  echo
  # --- Components ---
  section_header "Components"
  [[ -d "$run_dir/components/files/rootfs" ]] && kv "Files" "${C_OK}present${C_RESET}" || kv "Files" "${C_DIM}not found${C_RESET}"
  [[ -d "$run_dir/components/brew" ]] && kv "Homebrew" "${C_OK}present${C_RESET}" || kv "Homebrew" "${C_DIM}not found${C_RESET}"
  [[ -d "$run_dir/components/system" ]] && kv "System" "${C_OK}present${C_RESET}" || kv "System" "${C_DIM}not found${C_RESET}"
  [[ -d "$run_dir/components/keychain" ]] && kv "Keychain" "${C_OK}present${C_RESET}" || kv "Keychain" "${C_DIM}not found${C_RESET}"
  [[ -d "$run_dir/components/launchd" ]] && kv "Launchd" "${C_OK}present${C_RESET}" || kv "Launchd" "${C_DIM}not found${C_RESET}"

  echo
  if (( issues == 0 )); then
    success "No issues found."
  else
    warn "$issues issue(s) remaining."
  fi
}
