#!/usr/bin/env bash

resolve_template_tokens() {
  local source_file="$1"
  local target_file="$2"
  local source_home="${3:-$MACBACK_PRIMARY_HOME}"

  awk -v home="$source_home" '
    {
      gsub(/@HOME@/, home)
      print
    }
  ' "$source_file" > "$target_file"
}

default_include_template() {
  printf '%s\n' "$MACBACK_TEMPLATE_DIR/include-paths.txt.template"
}

default_exclude_template() {
  printf '%s\n' "$MACBACK_TEMPLATE_DIR/exclude-patterns.txt.template"
}

seed_effective_rules() {
  local working_dir="$1"
  local source_home="${2:-$MACBACK_PRIMARY_HOME}"

  ensure_dir "$working_dir"
  resolve_template_tokens "$(default_include_template)" "$working_dir/include-paths.txt" "$source_home"
  resolve_template_tokens "$(default_exclude_template)" "$working_dir/exclude-patterns.txt" "$source_home"
}
