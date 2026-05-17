# Changelog

All notable changes to WhisKey are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — Sprint 3

### Added
- Network Activity Monitor: egress audit with timestamp, URL, and event type logging (#33)
- Menu bar egress dot badge indicator (green for clean, orange for unexpected activity)
- Settings → Privacy tab with live egress log viewer and zero-egress claim
- Hold-vs-Tap state machine: Right Option hold >300ms triggers Push-to-Talk; double-tap within 300ms toggles Hands-Free mode
- Configurable disambiguation window (250–500ms, default 300ms) in Settings → Hotkey
- Voice Snippets: trigger-phrase text expansion with password manager and terminal security blocks (1Password, Bitwarden, KeePassXC, Terminal, iTerm2)
- Multi-hotkey bindings: four configurable hotkey actions (Default Transcription, Hands-Free Transcription, Open Popover, Inject Last Transcription) with conflict detection (#30)
- Settings → Snippets tab for snippet configuration
- Settings → Hotkeys tab with live key capture and 13-combo reserved block list

### Changed
- Hotkey interaction model now distinguishes hold duration and tap count (PR #31)
- `handsFreeEnabled` toggle replaces binary hotkey mode in Settings → Hotkey; collapses to PTT-only when off
- Accidental tap floor: presses <80ms are silently discarded

### Fixed
- PR #32 hotfix: state machine race condition in concurrent hotkey + transcription scenarios

### Security
- Voice snippet expansion blocked in password managers and terminals to prevent credential leaks
- Network egress audit ensures no unexpected outbound calls (#33)
