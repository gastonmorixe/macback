#!/usr/bin/env bats

setup() {
  load '../test_helper/common'
}

@test "build_restore_filters remaps home paths into user-relative filters" {
  local workdir="$BATS_TEST_TMPDIR/restore-filters"
  mkdir -p "$workdir"
  cat > "$workdir/include.txt" <<EOF
/Users/source/.ssh/**
/Users/source/Library/Preferences/com.googlecode.iterm2.plist
/Library/LaunchDaemons/com.local.macos-dev-sysctl-tuning.plist
EOF
  cat > "$workdir/exclude.txt" <<EOF
/Users/source/Library/CloudStorage/**
EOF
  cat > "$workdir/extra-user-excludes.txt" <<EOF
/Library/Preferences/com.googlecode.iterm2.plist
EOF

  run build_restore_filters \
    "$workdir/include.txt" \
    "$workdir/exclude.txt" \
    "/Users/source" \
    "/Users/tester" \
    "$workdir/system-include.txt" \
    "$workdir/user-include.txt" \
    "$workdir/extra-user-excludes.txt"
  assert_success
  assert_file_contains "$workdir/system-include.txt" "/Library/LaunchDaemons/com.local.macos-dev-sysctl-tuning.plist"
  assert_file_contains "$workdir/user-include.txt" "/.ssh/**"
  assert_file_contains "$workdir/user-include.txt" "/Library/Preferences/com.googlecode.iterm2.plist"
  assert_file_contains "$workdir/user-include.txt.exclude" "/Library/CloudStorage/**"
  assert_file_contains "$workdir/user-include.txt.exclude" "/Library/Preferences/com.googlecode.iterm2.plist"
}

@test "build_restore_filters supports nonstandard source home paths" {
  local workdir="$BATS_TEST_TMPDIR/restore-filters-alt-home"
  mkdir -p "$workdir"
  cat > "$workdir/include.txt" <<EOF
/opt/devhome/.config/zed/**
/opt/devhome/Library/Preferences/com.googlecode.iterm2.plist
EOF
  : > "$workdir/exclude.txt"

  run build_restore_filters \
    "$workdir/include.txt" \
    "$workdir/exclude.txt" \
    "/opt/devhome" \
    "/Users/tester" \
    "$workdir/system-include.txt" \
    "$workdir/user-include.txt"
  assert_success
  assert_file_contains "$workdir/user-include.txt" "/.config/zed/**"
  assert_file_contains "$workdir/user-include.txt" "/Library/Preferences/com.googlecode.iterm2.plist"
}
