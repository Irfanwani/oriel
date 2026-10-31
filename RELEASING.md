# Releasing Oriel

Oriel releases are tag-driven. Pushing a version tag builds and publishes the app; the Homebrew tap mirrors the published release automatically.

## One-time tap token setup

Immediate tap updates use a `TAP_TOKEN` secret in `Irfanwani/oriel`.

1. Create a fine-grained personal access token for **only** `Irfanwani/homebrew-oriel`.
2. Give it **Contents: Read and write** permission.
3. Add it to `Irfanwani/oriel` under **Settings → Secrets and variables → Actions** as `TAP_TOKEN`.

The token is optional. Without it, the tap's scheduled `Update cask` workflow checks GitHub Releases once an hour and mirrors the latest version.

## Release checklist

1. Bump the version in:
   - `Resources/Info.plist` (`CFBundleShortVersionString` and `CFBundleVersion`)
   - `scripts/oriel` (the `version` command)
   - `README.md` where the DMG filename or version is mentioned
2. Add a section to `CHANGELOG.md`.
3. Run the checks:

   ```sh
   ./scripts/test.sh
   ./scripts/build.sh
   ARCH=universal ./scripts/package.sh
   ```

4. Commit the version bump.
5. Tag and push:

   ```sh
   git tag -a v1.0.1 -m "Oriel 1.0.1"
   git push origin main
   git push origin v1.0.1
   ```

6. The **Release** workflow creates the GitHub Release and uploads the DMG + SHA256.
7. If `TAP_TOKEN` is configured, it dispatches the tap updater immediately. Otherwise the tap updates within an hour.
8. The tap workflow updates `Casks/oriel.rb`, verifies installation, and commits the new version/SHA.

## Homebrew tap maintenance

The tap lives at [Irfanwani/homebrew-oriel](https://github.com/Irfanwani/homebrew-oriel).

Manual update from the tap checkout:

```sh
./scripts/update-cask.sh          # latest stable release
./scripts/update-cask.sh v1.0.1   # a specific tag
```

The updater reads the release SHA256, validates it against `Oriel-<version>.dmg.sha256`, and only changes the cask when needed. After a manual edit to the cask, run the **Test cask** workflow or push normally; that workflow audits and installs the cask.

If an automatic update commits with the tap's `GITHUB_TOKEN`, GitHub does not start another workflow from that push. That is why the updater audits and installs the new cask in the same run before committing.

## Rolling back a cask

Point the cask at the previous version manually or run:

```sh
./scripts/update-cask.sh v1.0.0
```

Only tags with a published `Oriel-<version>.dmg` and matching `.sha256` asset will update successfully.
