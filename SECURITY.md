# Security policy

## Supported versions

The latest public release receives security fixes. There are no long-term support branches.

| Version | Supported |
| --- | --- |
| 1.0.x | Yes |
| Older | No |

## Reporting a vulnerability

Please **do not open a public issue** for a vulnerability with exploit details.

Use GitHub's private vulnerability reporting:

1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**.
3. Include the version, macOS version, reproduction steps and any relevant logs.

If private reporting is unavailable, contact the maintainer through the GitHub profile listed in `README.md` and ask for a private channel.

You can expect an acknowledgement within a few days. Fixes and credit will be coordinated before public disclosure.

## Privacy model

Oriel intentionally has a small attack surface:

- no networking code;
- no telemetry or analytics;
- no Screen Recording permission;
- no keyboard event tap or keystroke capture;
- no third-party dependencies;
- no app sandbox escape hatch or privileged helper.

Accessibility access is required to discover and reposition windows. The app reads window titles and geometry, and writes frame, raise and main-window attributes. It does not read window contents.

Oriel also observes pointer clicks and drags locally so manual window moves can be retiled and optional hover focus can work. Pointer data is used in memory only and is never written, stored or transmitted.

Settings and scenes are stored locally at:

```text
~/Library/Application Support/Oriel/settings.json
```

The URL scheme accepts `oriel://` requests from other local processes. Treat it like any other local automation surface: do not expose it through a network service.
