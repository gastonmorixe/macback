# macback Behavior Spec

## Core runtime rules

- The public entrypoint is `macback`.
- Backup and restore require root.
- Homebrew backup runs as the detected primary user.
- Homebrew restore runs as the selected target user.
- The destination picker must only offer real mounted volumes.
- The destination picker must show a compact identity line plus enough metadata
  to distinguish internal vs external mounts.
- The TUI must support:
  - `↑` / `↓` or `j` / `k` to move
  - `Enter` to accept
  - `Space` to toggle in multi-select
  - `a` select all visible
  - `u` unselect all visible
  - `/` filter
  - `q` cancel
- Plain text prompts must ignore arrow keys instead of printing escape
  sequences.

## Backup contract

- The tool chooses a destination base path, then either:
  - resumes/repairs the latest run
  - creates a new run
- Backup stores:
  - run metadata
  - manifest metadata
  - include/exclude rules
  - integrity files
  - system snapshot
  - optional Homebrew component
  - optional launchd metadata
  - optional keychain metadata
- On filesystems without POSIX metadata support, the tool must skip
  `rclone --metadata` and rely on the separate permissions inventory.

## Restore contract

- The tool validates manifests before restore.
- The tool warns when file verification state is non-zero or missing.
- User-home paths are remapped to the selected target home.
- The inspect and restore flows should show a serial-number match notice when
  the backup source serial equals the current Mac serial.

## TUI rendering contract

- Selector rows must not grow scrollback on navigation.
- Long rows must not wrap unpredictably.
- If an item needs more detail than fits comfortably, render the detail in a
  secondary dim line or bounded detail region rather than relying only on
  truncation.
