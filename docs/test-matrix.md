# macback Test Matrix

## Unit

- Destination mount validation
- Destination metadata formatting
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
- Homebrew-present and Homebrew-missing restore flows
