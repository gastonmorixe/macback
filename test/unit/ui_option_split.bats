#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "_tui_split_option separates label and description" {
  _tui_split_option "Backup|Create a new backup run"
  [[ "$_TUI_OPTION_LABEL" == "Backup" ]]
  [[ "$_TUI_OPTION_DESC" == "Create a new backup run" ]]
  [[ "$_TUI_OPTION_SUBTITLE" == "" ]]
}

@test "_tui_split_option extracts subtitle from third field" {
  _tui_split_option "ST1000LM1TB (/dev/disk4s2)|exfat • External • writable|/Volumes/ST1000LM1TB 1"
  [[ "$_TUI_OPTION_LABEL" == "ST1000LM1TB (/dev/disk4s2)" ]]
  [[ "$_TUI_OPTION_DESC" == "exfat • External • writable" ]]
  [[ "$_TUI_OPTION_SUBTITLE" == "/Volumes/ST1000LM1TB 1" ]]
}

@test "_tui_split_option handles label-only option" {
  _tui_split_option "Custom path"
  [[ "$_TUI_OPTION_LABEL" == "Custom path" ]]
  [[ "$_TUI_OPTION_DESC" == "" ]]
  [[ "$_TUI_OPTION_SUBTITLE" == "" ]]
}
