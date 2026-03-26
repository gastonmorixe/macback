# macback Test Matrix

## Unit

- Destination mount validation
- Destination metadata formatting
- Destination guard status passthrough
- Destination guard rejects stale targets before the child starts
- Destination pause/rebind flow for same-volume remounts
- Filter generation
- Template expansion
- Restore candidate discovery
- Restore filter remap
- Homebrew missing guidance
- Launchd metadata scope
- Manifest validation
- Serial notice logic

## Integration

- CLI help and unknown command behavior
- Root requirement for backup and restore
- Destination selection
- Restore source selection
- Inspect success and failure cases
- Resume/new-run decision behavior
- Destination guard and remount handling are currently covered by unit tests with mocked mount identity, not by a live unplug/replug integration test

## PTY / TUI

- Main menu arrow navigation
- Prompt arrow-key suppression
- Selector cancellation and back paths
- Multi-select toggling
- Filter mode behavior

## Operational fixtures

- Valid complete backup
- Invalid manifest
- Missing checksum
- ExFAT-like destination behavior
- Mocked destination disconnect/remount behavior
- Homebrew-present and Homebrew-missing restore flows
