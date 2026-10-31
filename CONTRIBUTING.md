# Contributing to Oriel

Thanks for helping make Oriel better. The project is small and deliberately boring: native macOS APIs, no third-party dependencies, and a strong bias toward keeping the desktop quiet.

## Good first contributions

- Reproduce a bug and add a focused test where it belongs.
- Improve accessibility labels, keyboard navigation or onboarding copy.
- Add a layout edge case to `Tests/OrielCoreTests.swift`.
- Fix a documentation error or clarify installation caveats.
- Share a macOS version and display setup where a layout behaves badly.

## Before opening a pull request

1. Search existing issues and pull requests.
2. Keep the change focused. One behavior, one fix.
3. Run the tests:

   ```sh
   ./scripts/test.sh
   ```

4. Build the app and smoke-test your change:

   ```sh
   ./scripts/build.sh
   open build/Oriel.app
   ```

5. If you touch layout geometry, add or update a unit test in `Tests/OrielCoreTests.swift`.
6. If you touch Settings, Onboarding or Overview, include a screenshot or a short recording in the pull request.

## Architecture notes

- **Core** is compiled as the Swift package target `OrielCore`. It should stay free of app lifecycle code and testable in isolation.
- **UI** contains SwiftUI views and AppKit window controllers. `SettingsView` and `OnboardingView` are hosted by `NSWindowController`s.
- **WindowManager** is the source of truth for discovered windows, per-display order, stacking, focus mode and floating membership.
- **LayoutEngine** is pure geometry. Prefer adding layout behavior there and keeping window mutation in `WindowManager`.
- **Preferences** is the only settings store. Mutate through `prefs.update { ... }`; it saves atomically and posts `.orielSettingsChanged`.
- **Accessibility** helpers must never read window contents. They are limited to frame, title, minimized/full-screen state and focus.

## Style

- Swift 5 language mode, macOS 14 deployment target.
- AppKit for windows and overlays; SwiftUI for settings and onboarding.
- No external packages unless there is a very good reason.
- Keep APIs `@MainActor` when they touch AppKit.
- Prefer clear names over clever abstractions.
- Match the existing formatting: four-space indentation, trailing commas where the codebase uses them.
- User-facing copy should be calm, specific and free of hype.

## Commit messages

Use a short imperative subject:

```text
Fix floating scene restore on secondary displays
Add Bento layout previews
Document ad-hoc signing caveats
```

## Reporting bugs

Please include:

- macOS version and Mac model;
- Oriel version (`oriel version`);
- display arrangement (including whether displays have different heights);
- the steps to reproduce;
- the **Troubleshooting…** report from the menu bar;
- a screenshot if the issue is visual.

Remove any personal information from screenshots and logs.

## Security and privacy

Oriel does not collect telemetry and does not need Screen Recording or Input Monitoring. Do not add networking, analytics, crash uploaders or event taps without a public design discussion first.

For a security concern, follow [SECURITY.md](SECURITY.md) rather than opening a public issue with exploit details.

## License

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE).
