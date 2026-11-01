# Changelog

All notable changes to Oriel are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-11-01

### Added

- Drag a tiled window onto another window to swap their positions. Command is no longer required.
- Drag the gap between the primary tile and the rest of the layout to resize the split.
- A visible divider grip and a highlighted drop target while dragging.
- An **Arrange** menu with resize, reset, swap, primary, float and window-cycle actions.

### Fixed

- Resizing now changes the layout in every layout, including Bento and ultrawide Side. Bento's asymmetric proportions and Side's rail range are preserved instead of silently clamping the change.
- The resize shortcut now reports when tiling is paused, Focus mode is active, or only a single tile is available, instead of claiming a resize that cannot happen.
- Clicking the desktop or a menu no longer leaves window dragging paused.
- Moving a window to another display with the swap shortcut now actually crosses the display boundary.
- Dragging across displays can move a window into another display's layout.

### Changed

- Version bumps on `main` now create the release tag automatically after tests pass, then publish the app and update the Homebrew tap.
- Release and local builds read the app version and build number from `Resources/Info.plist`.
- Homebrew cask updates are dispatched immediately after a release is published.
- The resize shortcut is described as resizing the main window rather than the active window.

## [1.0.0] - 2026-10-31

The first public release.

### Added

- Automatic window tiling with reflow when windows open, close or move.
- Five layouts: Grid, Columns, Rows, Side and Bento.
- Per-display layout, window count and ratio overrides.
- Stacked overflow windows and an optional floating-overflow mode.
- Active-window borders, all-window borders and glow modes.
- Focus mode with frame restoration on exit.
- No Peek privacy dimming and Clean Space across every display.
- Overview window map with keyboard navigation and stack fanning.
- Saved scenes with app launching, window order, floating frames and per-display settings.
- Floating app rules and an exclusion list for utility windows.
- Global keyboard shortcuts with Control + Option or Option + Command prefixes.
- Menu bar controls, onboarding, settings and diagnostics.
- `oriel` CLI and `oriel://` URL automation for layouts, counts, scenes, focus, floating, No Peek, Clean Space, Overview and Settings.
- Native AppKit + SwiftUI implementation with no third-party dependencies.
- Universal build script, ad-hoc signing, DMG packaging, SHA256 output and XCTest coverage.
- Homebrew cask support.

### Notes

- Oriel is ad-hoc signed and not notarized. Gatekeeper may require approval on first launch.
- Accessibility permission may need to be granted again after an update because the ad-hoc signature changes.
- macOS 14 Sonoma or later is required.
