#!/usr/bin/env bash

MACBACK_ROOT="${MACBACK_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export MACBACK_TEMPLATE_DIR="${MACBACK_ROOT}/templates"
export MACBACK_STATE_DIR="${MACBACK_STATE_DIR:-$MACBACK_ROOT/state}"
export MACBACK_OUTPUT_DIR="${MACBACK_OUTPUT_DIR:-$MACBACK_ROOT/output}"
export MACBACK_SPEC_VERSION="1"
export MACBACK_TOOL_VERSION="0.1.0"
export MACBACK_RCLONE_CHECK_SKIPPED_STATUS="skipped-resume-fast"
export MACBACK_MAX_MANIFEST_CHOICES="${MACBACK_MAX_MANIFEST_CHOICES:-40}"
export MACBACK_MAX_PREVIEW_LINES="${MACBACK_MAX_PREVIEW_LINES:-120}"

is_tty() {
  [[ -t 0 && -t 1 ]]
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  local cmd="$1"
  if ! has_cmd "$cmd"; then
    echo "Missing required command: $cmd" >&2
    return 1
  fi
}

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "This tool must run as root." >&2
    echo "Run it with sudo or as root." >&2
    return 1
  fi
}

detect_primary_user() {
  if [[ -n "${MACBACK_PRIMARY_USER:-}" ]]; then
    printf '%s\n' "$MACBACK_PRIMARY_USER"
    return 0
  fi

  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s\n' "$SUDO_USER"
    return 0
  fi

  stat -f '%Su' /dev/console 2>/dev/null || id -un
}

detect_primary_home() {
  local user="${1:-$(detect_primary_user)}"
  local home=""

  home="$(dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
  if [[ -n "$home" ]]; then
    printf '%s\n' "$home"
    return 0
  fi

  eval "printf '%s\n' ~$user"
}

MACBACK_PRIMARY_USER="${MACBACK_PRIMARY_USER:-$(detect_primary_user)}"
MACBACK_PRIMARY_HOME="${MACBACK_PRIMARY_HOME:-$(detect_primary_home "$MACBACK_PRIMARY_USER")}"

detect_machine_serial() {
  if [[ -n "${MACBACK_MACHINE_SERIAL:-}" ]]; then
    printf '%s\n' "$MACBACK_MACHINE_SERIAL"
    return 0
  fi

  ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformSerialNumber/{print $(NF-1); exit}'
}

MACBACK_MACHINE_SERIAL="${MACBACK_MACHINE_SERIAL:-$(detect_machine_serial)}"

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

timestamp_id() {
  date +"%Y%m%d-%H%M%S"
}

sanitize_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]._-' '-' | sed 's/^-*//; s/-*$//'
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

json_file_array() {
  local file="$1"
  local first=true
  echo "["
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    if $first; then
      first=false
    else
      echo ","
    fi
    printf '  "%s"' "$(json_escape "$line")"
  done < "$file"
  echo
  echo "]"
}

ensure_dir() {
  mkdir -p "$1"
}

copy_or_link_dir() {
  local src="$1"
  local dst="$2"
  cp -R "$src" "$dst"
}

detect_machine_id() {
  local name
  name="$(scutil --get ComputerName 2>/dev/null || hostname)"
  sanitize_name "$name"
}

detect_target_users() {
  find /Users -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
    | sed 's#^/Users/##' \
    | grep -vE '^(Shared|Guest|Deleted Users)$' \
    | sort
}

count_non_comment_lines() {
  local file="$1"
  awk 'NF && $0 !~ /^[[:space:]]*#/' "$file" | wc -l | tr -d ' '
}

list_run_manifests() {
  local base="${1:-/Volumes}"
  local search_roots=()
  if [[ "$base" == "/Volumes" ]]; then
    local volume
    while IFS= read -r volume; do
      [[ -d "$volume/macback" ]] && search_roots+=("$volume/macback")
    done < <(discover_destination_roots)
  else
    search_roots+=("$base")
  fi

  local root
  for root in "${search_roots[@]}"; do
    find "$root" -mindepth 4 -maxdepth 4 -type f -path '*/meta/manifest.json' 2>/dev/null || true
  done
}

list_run_dirs() {
  local base="${1:-/Volumes}"
  local search_roots=()
  if [[ "$base" == "/Volumes" ]]; then
    local volume
    while IFS= read -r volume; do
      [[ -d "$volume/macback" ]] && search_roots+=("$volume/macback")
    done < <(discover_destination_roots)
  else
    search_roots+=("$base")
  fi

  local root
  for root in "${search_roots[@]}"; do
    find "$root" -mindepth 4 -maxdepth 4 -type f -path '*/meta/run.env' 2>/dev/null || true
  done | while IFS= read -r f; do
    dirname "$(dirname "$f")"
  done | sort -u
}

path_is_under() {
  local path="$1"
  local parent="$2"
  [[ "$path" == "$parent"* ]]
}

trim_trailing_space() {
  printf '%s' "$1" | sed 's/[[:space:]]*$//'
}

path_fs_type() {
  local path="$1"
  diskutil info "$path" 2>/dev/null | awk -F': *' '/Type \(Bundle\)/{print tolower($2); exit}'
}

path_supports_metadata() {
  local path="$1"
  local fs_type
  fs_type="$(path_fs_type "$path")"
  case "$fs_type" in
    apfs|hfs|hfsplus|hfsx) return 0 ;;
    *) return 1 ;;
  esac
}

run_as_user_capture() {
  local user="$1"
  shift
  sudo -H -u "$user" "$@"
}

pid_is_running() {
  local pid="$1"
  [[ -n "$pid" ]] || return 1
  ps -p "$pid" >/dev/null 2>&1
}

rclone_check_status_is_skipped() {
  [[ "${1:-}" == "$MACBACK_RCLONE_CHECK_SKIPPED_STATUS" ]]
}
