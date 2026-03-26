#!/usr/bin/env bash

write_run_env() {
  local out_file="$1"
  shift
  : > "$out_file"
  while [[ $# -gt 1 ]]; do
    printf '%s=%q\n' "$1" "$2" >> "$out_file"
    shift 2
  done
}

write_run_json() {
  local out_file="$1"
  local created_at="$2"
  local started_at="$3"
  local finished_at="$4"
  local status="$5"
  local destination_base="$6"
  local run_dir="$7"
  local source_user="$8"
  local source_home="$9"
  local source_serial="${10:-}"

  cat > "$out_file" <<EOF
{
  "spec_version": "$MACBACK_SPEC_VERSION",
  "tool_version": "$MACBACK_TOOL_VERSION",
  "created_at": "$(json_escape "$created_at")",
  "started_at": "$(json_escape "$started_at")",
  "finished_at": "$(json_escape "$finished_at")",
  "status": "$(json_escape "$status")",
  "destination_base": "$(json_escape "$destination_base")",
  "run_dir": "$(json_escape "$run_dir")",
  "source_user": "$(json_escape "$source_user")",
  "source_home": "$(json_escape "$source_home")",
  "source_serial": "$(json_escape "$source_serial")"
}
EOF
}

write_manifest_json() {
  local out_file="$1"
  local run_dir="$2"
  local files_enabled="$3"
  local brew_enabled="$4"
  local keychain_enabled="$5"
  local system_enabled="$6"
  local launchd_enabled="$7"
  local target_home_mode="$8"
  local ownership_mode="$9"

  cat > "$out_file" <<EOF
{
  "spec_version": "$MACBACK_SPEC_VERSION",
  "tool_version": "$MACBACK_TOOL_VERSION",
  "run_dir": "$(json_escape "$run_dir")",
  "components": {
    "files": $files_enabled,
    "brew": $brew_enabled,
    "keychain": $keychain_enabled,
    "system_snapshot": $system_enabled,
    "launchd": $launchd_enabled
  },
  "restore_defaults": {
    "home_mapping_mode": "$(json_escape "$target_home_mode")",
    "ownership_mode": "$(json_escape "$ownership_mode")"
  }
}
EOF
}

manifest_component_enabled() {
  local manifest="$1"
  local key="$2"
  plutil -extract "components.$key" raw -o - "$manifest" 2>/dev/null
}

write_integrity_checksums() {
  local integrity_dir="$1"
  shift
  ensure_dir "$integrity_dir"
  local checksum_file="$integrity_dir/manifest.sha256"
  : > "$checksum_file"
  local file
  for file in "$@"; do
    [[ -f "$file" ]] || continue
    shasum -a 256 "$file" >> "$checksum_file"
  done
}

load_run_env() {
  local env_file="$1"
  # shellcheck disable=SC1090
  source "$env_file"
}

validate_backup_manifest() {
  local manifest="$1"
  [[ -f "$manifest" ]] || return 1
  local meta_dir
  meta_dir="$(dirname "$manifest")"
  local run_dir
  run_dir="$(dirname "$meta_dir")"
  [[ -f "$meta_dir/run.env" ]] || return 1
  [[ -f "$meta_dir/run.json" ]] || return 1
  [[ -f "$meta_dir/include-paths.txt" ]] || return 1
  [[ -f "$meta_dir/exclude-patterns.txt" ]] || return 1
  plutil -convert json -o /dev/null "$manifest" >/dev/null 2>&1 || return 1
  plutil -convert json -o /dev/null "$meta_dir/run.json" >/dev/null 2>&1 || return 1
  grep -F '"spec_version"' "$manifest" >/dev/null 2>&1 || return 1
  grep -F '"components"' "$manifest" >/dev/null 2>&1 || return 1
  grep -F 'SOURCE_HOME=' "$meta_dir/run.env" >/dev/null 2>&1 || return 1
  grep -F 'SOURCE_USER=' "$meta_dir/run.env" >/dev/null 2>&1 || return 1

  if [[ "$(manifest_component_enabled "$manifest" files)" == "true" ]]; then
    [[ -d "$run_dir/components/files/rootfs" ]] || return 1
  fi
  if [[ "$(manifest_component_enabled "$manifest" brew)" == "true" ]]; then
    [[ -d "$run_dir/components/brew" ]] || return 1
    [[ -f "$run_dir/components/brew/Brewfile" ]] || return 1
  fi
  if [[ "$(manifest_component_enabled "$manifest" keychain)" == "true" ]]; then
    [[ -d "$run_dir/components/keychain" ]] || return 1
  fi
  if [[ "$(manifest_component_enabled "$manifest" launchd)" == "true" ]]; then
    [[ -d "$run_dir/components/launchd" ]] || return 1
  fi
  if [[ "$(manifest_component_enabled "$manifest" system_snapshot)" == "true" ]]; then
    [[ -d "$run_dir/components/system" ]] || return 1
  fi
}

verify_manifest_checksums() {
  local manifest="$1"
  local meta_dir
  meta_dir="$(dirname "$manifest")"
  local checksum_file="$meta_dir/integrity/manifest.sha256"
  [[ -f "$checksum_file" ]] || return 2
  (cd "$meta_dir/integrity" && shasum -a 256 -c "$(basename "$checksum_file")" >/dev/null 2>&1)
}

read_files_verification_status() {
  local manifest="$1"
  local meta_dir
  meta_dir="$(dirname "$manifest")"
  local status_file="$meta_dir/integrity/rclone-check.exit-code"
  [[ -f "$status_file" ]] || return 2
  cat "$status_file"
}
