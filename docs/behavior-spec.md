# macback Behavior Spec

## Core runtime rules

- The public entrypoint is `macback`.
- Backup and restore require root.
- Homebrew backup runs as the detected **primary user**.
- Homebrew restore runs as the selected **target user**.
- The destination picker only offers real mounted volumes.
- The destination picker shows a compact identity line plus enough metadata to distinguish internal vs external mounts.
- The TUI supports:
  - `↑` / `↓` or `j` / `k` to move
  - `Enter` to accept
  - `Space` to toggle in multi-select
  - `a` select all visible
  - `u` unselect all visible
  - `/` filter
  - `q` cancel
- Plain text prompts ignore arrow keys instead of printing escape sequences.

## Backup contract

- The tool picks a destination base path, then either resumes/repairs the latest run or creates a new one.
- Backup stores:
  - run metadata
  - manifest metadata
  - include/exclude rules
  - integrity files
  - system snapshot
  - optional Homebrew component
  - optional launchd metadata
  - optional keychain metadata
- On filesystems without POSIX metadata support, the tool skips `rclone --metadata` and relies on the separate permissions inventory.

## Restore contract

- The tool validates manifests before restore.
- The tool warns when file verification state is non-zero or missing.
- User-home paths are remapped to the selected target home.
- The inspect and restore flows show a serial-number match notice when the backup source serial equals the current Mac serial.

## TUI rendering contract

- Selector rows do not grow scrollback on navigation.
- Long rows do not wrap unpredictably.
- If an item needs more detail than fits on one line, it renders in a secondary dim line or bounded detail region instead of relying on truncation alone.
