# Changelog

All notable changes to Oriel are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/).

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
