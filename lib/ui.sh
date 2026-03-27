#!/usr/bin/env bash

if is_tty; then
  C_RESET=$'\033[0m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_ACCENT=$'\033[38;5;75m'
  C_WARN=$'\033[38;5;214m'
  C_ERROR=$'\033[38;5;203m'
  C_OK=$'\033[38;5;77m'
  C_CHROME=$'\033[38;5;240m'
  C_SELECT=$'\033[38;5;77m'
else
  C_RESET=""
  C_DIM=""
  C_BOLD=""
  C_ACCENT=""
  C_WARN=""
  C_ERROR=""
  C_OK=""
  C_CHROME=""
  C_SELECT=""
fi

ui_term_width() {
  tput cols 2>/dev/null || echo 80
}

ui_can_use_tty() {
  if [[ -n "${MACBACK_TEST_TTY_STDIO:-}" ]]; then
    return 0
  fi
  [[ -z "${MACBACK_PLAIN_UI:-}" ]] && [[ -r /dev/tty && -w /dev/tty ]]
}

ui_printf() {
  local fmt="$1"
  shift
  if [[ -n "${MACBACK_TEST_TTY_STDIO:-}" ]]; then
    # shellcheck disable=SC2059
    printf "$fmt" "$@"
  elif ui_can_use_tty; then
    # shellcheck disable=SC2059
    printf "$fmt" "$@" > /dev/tty
  else
    # shellcheck disable=SC2059
    printf "$fmt" "$@"
  fi
}

ui_println() {
  ui_printf '%b\n' "$1"
}

ui_read_line() {
  if [[ -n "${MACBACK_TEST_TTY_STDIO:-}" ]]; then
    IFS= read -r REPLY
  elif ui_can_use_tty; then
    IFS= read -r REPLY < /dev/tty
  else
    IFS= read -r REPLY
  fi
}

ui_read_prompt_line() {
  if [[ -n "${MACBACK_TEST_TTY_STDIO:-}" ]]; then
    ui_read_line
    return 0
  fi
  if ! ui_can_use_tty; then
    ui_read_line
    return 0
  fi

  local buf="" key seq
  while true; do
    IFS= read -rsn1 key < /dev/tty
    case "$key" in
      "")
        REPLY="$buf"
        ui_println ""
        return 0
        ;;
      $'\x7f'|$'\b')
        if [[ -n "$buf" ]]; then
          buf="${buf%?}"
          ui_printf '\b \b'
        fi
        ;;
      $'\x1b')
        IFS= read -rsn1 -t 0.01 seq < /dev/tty || true
        if [[ "$seq" == "[" || "$seq" == "O" ]]; then
          IFS= read -rsn1 -t 0.01 seq < /dev/tty || true
        fi
        ;;
      *)
        buf+="$key"
        ui_printf '%s' "$key"
        ;;
    esac
  done
}

ui_read_key() {
  if [[ -n "${MACBACK_TEST_TTY_STDIO:-}" ]]; then
    IFS= read -rsn1 REPLY
  elif ui_can_use_tty; then
    IFS= read -rsn1 REPLY < /dev/tty
  else
    IFS= read -rsn1 REPLY
  fi
}

ui_move_up() {
  local lines="$1"
  (( lines > 0 )) || return 0
  ui_printf '\033[%dA' "$lines"
}

ui_clear_line() {
  ui_printf '\033[2K\r'
}

ui_tput() {
  local cap="$1"
  if [[ -n "${MACBACK_TEST_TTY_STDIO:-}" ]]; then
    tput "$cap" 2>/dev/null || true
  elif ui_can_use_tty; then
    tput "$cap" > /dev/tty 2>/dev/null || true
  else
    tput "$cap" 2>/dev/null || true
  fi
}

print_banner() {
  local title="$1"
  ui_println "  ${C_BOLD}${C_ACCENT}${title}${C_RESET} ${C_CHROME}v${MACBACK_TOOL_VERSION}${C_RESET}"
  ui_println "  ${C_CHROME}macOS backup and restore · ${MACBACK_REPO}${C_RESET}"
  ui_println ""
}

section_header() {
  ui_println "${C_BOLD}${C_ACCENT}$1${C_RESET}"
}

kv() {
  ui_printf '  %b%-18s%b %s\n' "$C_DIM" "$1" "$C_RESET" "$2"
}

box() {
  local line
  ui_println "  ${C_CHROME}╭──────────────────────────────────────────────╮${C_RESET}"
  for line in "$@"; do
    ui_printf '  %b│%b %-44s %b│%b\n' "$C_CHROME" "$C_RESET" "$line" "$C_CHROME" "$C_RESET"
  done
  ui_println "  ${C_CHROME}╰──────────────────────────────────────────────╯${C_RESET}"
}

info() {
  ui_println "${C_ACCENT}$*${C_RESET}"
}

success() {
  ui_println "${C_OK}$*${C_RESET}"
}

warn() {
  echo -e "${C_WARN}$*${C_RESET}" >&2
}

error() {
  echo -e "${C_ERROR}$*${C_RESET}" >&2
}

dim() {
  ui_println "${C_DIM}$*${C_RESET}"
}

prompt() {
  ui_printf '  %b%s%b %b❯%b ' "$C_DIM" "$1" "$C_RESET" "$C_SELECT" "$C_RESET"
}

confirm() {
  local label="${1:-Continue?}"
  prompt "$label [y/N]"
  local reply
  ui_read_prompt_line
  reply="$REPLY"
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

_tui_matches_filter() {
  local value="$1"
  local filter="$2"
  [[ -z "$filter" ]] && return 0
  local lhs rhs
  lhs="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  rhs="$(printf '%s' "$filter" | tr '[:upper:]' '[:lower:]')"
  [[ "$lhs" == *"$rhs"* ]]
}

_tui_split_option() {
  local raw="$1"
  _TUI_OPTION_LABEL="${raw%%|*}"
  _TUI_OPTION_SUBTITLE=""
  if [[ "$raw" == *"|"* ]]; then
    local rest="${raw#*|}"
    if [[ "$rest" == *"|"* ]]; then
      _TUI_OPTION_DESC="${rest%%|*}"
      _TUI_OPTION_SUBTITLE="${rest#*|}"
    else
      _TUI_OPTION_DESC="$rest"
    fi
  else
    _TUI_OPTION_DESC=""
  fi
}

_tui_format_single_line() {
  local raw="$1"
  _tui_split_option "$raw"
  local width=$(( $(ui_term_width) - 6 ))
  (( width < 20 )) && width=20
  local out
  if [[ -n "$_TUI_OPTION_DESC" ]]; then
    out="$(printf '%-14s %s' "$_TUI_OPTION_LABEL" "$_TUI_OPTION_DESC")"
  else
    out="$_TUI_OPTION_LABEL"
  fi
  if (( ${#out} > width )); then
    printf '%s…' "${out:0:$((width - 1))}"
  else
    printf '%s' "$out"
  fi
}

_tui_format_multi_line() {
  local raw="$1"
  _tui_split_option "$raw"
  local width=$(( $(ui_term_width) - 10 ))
  (( width < 20 )) && width=20
  local out
  if [[ -n "$_TUI_OPTION_DESC" ]]; then
    out="$(printf '%-14s %s' "$_TUI_OPTION_LABEL" "$_TUI_OPTION_DESC")"
  else
    out="$_TUI_OPTION_LABEL"
  fi
  if (( ${#out} > width )); then
    printf '%s…' "${out:0:$((width - 1))}"
  else
    printf '%s' "$out"
  fi
}

_tui_build_visible_indices() {
  local filter="$1"
  shift
  local options=("$@")
  local i
  _TUI_VISIBLE_INDICES=()
  for ((i=0; i<${#options[@]}; i++)); do
    if _tui_matches_filter "${options[$i]}" "$filter"; then
      _TUI_VISIBLE_INDICES+=("$i")
    fi
  done
}

_tui_draw_single() {
  local title="$1"
  local filter="$2"
  local filter_mode="$3"
  local status="$4"
  local cursor="$5"
  local top="$6"
  local max_rows="$7"
  shift 7
  local options=("$@")
  local row visible_pos idx line filter_label
  filter_label="${filter:-<none>}"
  $filter_mode && filter_label="/${filter}"
  ui_clear_line
  ui_println "${C_BOLD}${C_ACCENT}${title}${C_RESET}"
  ui_clear_line
  ui_println "  ${C_DIM}↑↓ move • enter select • / filter • q cancel${C_RESET}"
  ui_clear_line
  ui_println "  ${C_DIM}Filter: ${filter_label}${C_RESET}"
  ui_clear_line
  ui_println "  ${C_DIM}${status}${C_RESET}"
  _TUI_TOTAL_DRAWN=0
  for ((row=0; row<max_rows; row++)); do
    ui_clear_line
    visible_pos=$((top + row))
    if (( visible_pos < ${#_TUI_VISIBLE_INDICES[@]} )); then
      idx="${_TUI_VISIBLE_INDICES[$visible_pos]}"
      _tui_split_option "${options[$idx]}"
      line="$(_tui_format_single_line "${options[$idx]}")"
      if (( visible_pos == cursor )); then
        ui_println "  ${C_SELECT}❯${C_RESET} ${C_BOLD}${line}${C_RESET}"
      else
        ui_println "    ${C_DIM}${line}${C_RESET}"
      fi
      _TUI_TOTAL_DRAWN=$((_TUI_TOTAL_DRAWN + 1))
      if [[ -n "$_TUI_OPTION_SUBTITLE" ]]; then
        ui_clear_line
        ui_println "      ${C_DIM}${_TUI_OPTION_SUBTITLE}${C_RESET}"
        _TUI_TOTAL_DRAWN=$((_TUI_TOTAL_DRAWN + 1))
      fi
    else
      ui_println ""
      _TUI_TOTAL_DRAWN=$((_TUI_TOTAL_DRAWN + 1))
    fi
  done
  while (( _TUI_TOTAL_DRAWN < ${_TUI_PREV_DRAWN:-0} )); do
    ui_clear_line
    ui_println ""
    _TUI_TOTAL_DRAWN=$((_TUI_TOTAL_DRAWN + 1))
  done
  _TUI_PREV_DRAWN="$_TUI_TOTAL_DRAWN"
}

_tui_draw_multi() {
  local title="$1"
  local filter="$2"
  local filter_mode="$3"
  local status="$4"
  local cursor="$5"
  local top="$6"
  local max_rows="$7"
  shift 7
  local options=("$@")
  local row visible_pos idx line mark filter_label
  filter_label="${filter:-<none>}"
  $filter_mode && filter_label="/${filter}"
  ui_clear_line
  ui_println "${C_BOLD}${C_ACCENT}${title}${C_RESET}"
  ui_clear_line
  ui_println "  ${C_DIM}↑↓ move • space toggle • a all • u none • / filter • enter confirm${C_RESET}"
  ui_clear_line
  ui_println "  ${C_DIM}Filter: ${filter_label} • Selected: ${_TUI_SELECTED_COUNT}${C_RESET}"
  ui_clear_line
  ui_println "  ${C_DIM}${status}${C_RESET}"
  for ((row=0; row<max_rows; row++)); do
    ui_clear_line
    visible_pos=$((top + row))
    if (( visible_pos < ${#_TUI_VISIBLE_INDICES[@]} )); then
      idx="${_TUI_VISIBLE_INDICES[$visible_pos]}"
      line="$(_tui_format_multi_line "${options[$idx]}")"
      if (( visible_pos == cursor )); then
        ui_println "  ${C_SELECT}❯${C_RESET} ${C_BOLD}${line}${C_RESET}"
      else
        ui_println "    ${C_DIM}${line}${C_RESET}"
      fi
    else
      ui_println ""
      fi
    done
}

tui_single_select() {
  local title="$1"
  shift
  local options=("$@")
  local count="${#options[@]}"
  if ! ui_can_use_tty; then
    local i
    printf '%s\n' "$title" >&2
    for ((i=0; i<count; i++)); do
      printf '  %d) %s\n' "$((i + 1))" "${options[$i]}" >&2
    done
    printf '  Choice [1-%d]: ' "$count" >&2
    ui_read_line
    if [[ "$REPLY" =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= count )); then
      _TUI_SELECTED=$((REPLY - 1))
      _tui_split_option "${options[$_TUI_SELECTED]}"
      _TUI_VALUE="$_TUI_OPTION_LABEL"
      printf '%s\n' "$_TUI_VALUE"
      return 0
    fi
    return 1
  fi

  local filter="" cursor=0 top=0 filter_mode=false status=""
  local max_rows=12
  (( count < max_rows )) && max_rows="$count"
  (( max_rows < 1 )) && max_rows=1
  _tui_build_visible_indices "$filter" "${options[@]}"
  _TUI_PREV_DRAWN=0
  ui_tput civis
  trap 'ui_tput cnorm; trap - RETURN' RETURN
  _tui_draw_single "$title" "$filter" "$filter_mode" "$status" "$cursor" "$top" "$max_rows" "${options[@]}"
  local rendered_lines=$((4 + _TUI_TOTAL_DRAWN))

  while true; do
    ui_read_key
    local key="$REPLY"
    if $filter_mode; then
      case "$key" in
        "")
          filter_mode=false
          status=""
          ;;
        $'\x7f'|$'\b')
          filter="${filter%?}"
          ;;
        $'\x1b')
          filter_mode=false
          status=""
          ;;
        *)
          filter+="$key"
          ;;
      esac
      _tui_build_visible_indices "$filter" "${options[@]}"
      cursor=0
      top=0
      status=""
      ui_move_up "$rendered_lines"
      _tui_draw_single "$title" "$filter" "$filter_mode" "$status" "$cursor" "$top" "$max_rows" "${options[@]}"
      rendered_lines=$((4 + _TUI_TOTAL_DRAWN))
      continue
    fi
    case "$key" in
      $'\x1b')
        ui_read_key
        if [[ "$REPLY" == "[" ]]; then
          ui_read_key
          case "$REPLY" in
            A) (( cursor > 0 )) && cursor=$((cursor - 1)) ;;
            B) (( cursor + 1 < ${#_TUI_VISIBLE_INDICES[@]} )) && cursor=$((cursor + 1)) ;;
          esac
        fi
        ;;
      k) (( cursor > 0 )) && cursor=$((cursor - 1)) ;;
      j) (( cursor + 1 < ${#_TUI_VISIBLE_INDICES[@]} )) && cursor=$((cursor + 1)) ;;
      /)
        filter_mode=true
        status="Type to filter. Enter to apply. Esc to cancel."
        ;;
      "")
        if (( ${#_TUI_VISIBLE_INDICES[@]} > 0 )); then
          _TUI_SELECTED="${_TUI_VISIBLE_INDICES[$cursor]}"
          _tui_split_option "${options[$_TUI_SELECTED]}"
          _TUI_VALUE="$_TUI_OPTION_LABEL"
          ui_tput cnorm
          trap - RETURN
          ui_println ""
          printf '%s\n' "$_TUI_VALUE"
          return 0
        fi
        ;;
      q)
        ui_tput cnorm
        trap - RETURN
        ui_println ""
        return 1
        ;;
    esac

    (( cursor < top )) && top="$cursor"
    (( cursor >= top + max_rows )) && top=$((cursor - max_rows + 1))
    ui_move_up "$rendered_lines"
    _tui_draw_single "$title" "$filter" "$filter_mode" "$status" "$cursor" "$top" "$max_rows" "${options[@]}"
    rendered_lines=$((4 + _TUI_TOTAL_DRAWN))
  done
}

choose_from_lines() {
  local title="$1"
  shift
  tui_single_select "$title" "$@"
}

choose_many_from_lines() {
  local title="$1"
  shift
  local options=("$@")
  local count="${#options[@]}"
  if ! ui_can_use_tty; then
    local i
    printf '%s\n' "$title" >&2
    for ((i=0; i<count; i++)); do
      printf '  %d) [x] %s\n' "$((i + 1))" "${options[$i]}" >&2
    done
    printf '  Numbers to exclude (comma-separated, Enter for all): ' >&2
    ui_read_line
    local raw="$REPLY"
    local mark=()
    for ((i=0; i<count; i++)); do mark[i]=1; done
    if [[ -n "$raw" ]]; then
      local normalized
      normalized="$(printf '%s' "$raw" | tr ',' ' ')"
      local n
      for n in $normalized; do
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= count )); then
          mark[n - 1]=0
        fi
      done
    fi
    for ((i=0; i<count; i++)); do
      if (( mark[i] == 1 )); then
        _tui_split_option "${options[$i]}"
        printf '%s\n' "$_TUI_OPTION_LABEL"
      fi
    done
    return 0
  fi

  local filter="" cursor=0 top=0 filter_mode=false status=""
  local max_rows=12
  (( count < max_rows )) && max_rows="$count"
  (( max_rows < 1 )) && max_rows=1
  _TUI_MARKS=()
  _TUI_SELECTED_COUNT=0
  local i
  for ((i=0; i<count; i++)); do
    _TUI_MARKS[i]=1
    _TUI_SELECTED_COUNT=$((_TUI_SELECTED_COUNT + 1))
  done
  _tui_build_visible_indices "$filter" "${options[@]}"
  local rendered_lines=$((4 + max_rows))
  ui_tput civis
  trap 'ui_tput cnorm; trap - RETURN' RETURN
  _tui_draw_multi "$title" "$filter" "$filter_mode" "$status" "$cursor" "$top" "$max_rows" "${options[@]}"

  while true; do
    ui_read_key
    local key="$REPLY"
    if $filter_mode; then
      case "$key" in
        "")
          filter_mode=false
          status=""
          ;;
        $'\x7f'|$'\b')
          filter="${filter%?}"
          ;;
        $'\x1b')
          filter_mode=false
          status=""
          ;;
        *)
          filter+="$key"
          ;;
      esac
      _tui_build_visible_indices "$filter" "${options[@]}"
      cursor=0
      top=0
      status=""
      ui_move_up "$rendered_lines"
      _tui_draw_multi "$title" "$filter" "$filter_mode" "$status" "$cursor" "$top" "$max_rows" "${options[@]}"
      continue
    fi
    case "$key" in
      $'\x1b')
        ui_read_key
        if [[ "$REPLY" == "[" ]]; then
          ui_read_key
          case "$REPLY" in
            A) (( cursor > 0 )) && cursor=$((cursor - 1)) ;;
            B) (( cursor + 1 < ${#_TUI_VISIBLE_INDICES[@]} )) && cursor=$((cursor + 1)) ;;
          esac
        fi
        ;;
      k) (( cursor > 0 )) && cursor=$((cursor - 1)) ;;
      j) (( cursor + 1 < ${#_TUI_VISIBLE_INDICES[@]} )) && cursor=$((cursor + 1)) ;;
      " ")
        if (( ${#_TUI_VISIBLE_INDICES[@]} > 0 )); then
          local idx="${_TUI_VISIBLE_INDICES[$cursor]}"
          if (( _TUI_MARKS[idx] == 1 )); then
            _TUI_MARKS[idx]=0
            _TUI_SELECTED_COUNT=$((_TUI_SELECTED_COUNT - 1))
          else
            _TUI_MARKS[idx]=1
            _TUI_SELECTED_COUNT=$((_TUI_SELECTED_COUNT + 1))
          fi
        fi
        ;;
      a)
        local idx
        for idx in "${_TUI_VISIBLE_INDICES[@]}"; do
          if (( _TUI_MARKS[idx] == 0 )); then
            _TUI_MARKS[idx]=1
            _TUI_SELECTED_COUNT=$((_TUI_SELECTED_COUNT + 1))
          fi
        done
        ;;
      u)
        local idx
        for idx in "${_TUI_VISIBLE_INDICES[@]}"; do
          if (( _TUI_MARKS[idx] == 1 )); then
            _TUI_MARKS[idx]=0
            _TUI_SELECTED_COUNT=$((_TUI_SELECTED_COUNT - 1))
          fi
        done
        ;;
      /)
        filter_mode=true
        status="Type to filter. Enter to apply. Esc to cancel."
        ;;
      "")
        ui_tput cnorm
        trap - RETURN
        ui_println ""
        for ((i=0; i<count; i++)); do
          if (( _TUI_MARKS[i] == 1 )); then
            _tui_split_option "${options[$i]}"
            printf '%s\n' "$_TUI_OPTION_LABEL"
          fi
        done
        return 0
        ;;
      q)
        ui_tput cnorm
        trap - RETURN
        ui_println ""
        return 1
        ;;
    esac

    (( cursor < top )) && top="$cursor"
    (( cursor >= top + max_rows )) && top=$((cursor - max_rows + 1))
    ui_move_up "$rendered_lines"
    rendered_lines=$((4 + max_rows))
    _tui_draw_multi "$title" "$filter" "$filter_mode" "$status" "$cursor" "$top" "$max_rows" "${options[@]}"
  done
}
