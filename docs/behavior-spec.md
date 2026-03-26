# macback Behavior Spec

## Core runtime rules

- The public entrypoint is `macback`.
- Backup and restore require root.
- Homebrew backup runs as the detected **primary user**.
- Homebrew restore runs as the selected **target user**.
- The destination picker only offers real mounted volumes.
- The tool refuses stale `/Volumes/...` paths that are not live mounted volumes before creating or resuming a run.
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
- The files component runs `rclone` under a parallel destination guard.
- The guard records the selected mount root, filesystem device id, and volume UUID when available.
- While `rclone` runs, the guard checks that destination identity every 2 seconds.
- If the destination changes or disconnects, the tool stops `rclone` and pauses the backup instead of continuing on a stale path.
- If the same volume remounts elsewhere and the UUID still matches, the tool can offer to continue the same run on the remounted path.
- The files backup uses `rclone --inplace` so final file writes do not depend on temp-file rename behavior.
- When resuming an existing backup run, the tool skips the full post-copy `rclone check` and records that verification was intentionally skipped for fast resume.
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
- The destination guard is supervisory, not per-write: writes already in flight may still complete or fail before the guard stops `rclone`.

## Restore contract

- The tool validates manifests before restore.
- The tool warns when file verification state is non-zero or missing.
- User-home paths are remapped to the selected target home.
- The inspect and restore flows show a serial-number match notice when the backup source serial equals the current Mac serial.

## TUI rendering contract

- Selector rows do not grow scrollback on navigation.
- Long rows do not wrap unpredictably.
- If an item needs more detail than fits on one line, it renders in a secondary dim line or bounded detail region instead of relying on truncation alone.
