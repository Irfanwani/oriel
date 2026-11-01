# Releasing Oriel

Oriel uses tag-based releases. A version bump pushed to `main` is tagged and released automatically once the **Test** workflow passes. The published release then flows into the Homebrew tap without manual edits.

## One-time tap token setup

Immediate tap updates use a `TAP_TOKEN` secret in `Irfanwani/oriel`.

1. Create a fine-grained personal access token for **only** `Irfanwani/homebrew-oriel`.
2. Give it **Contents: Read and write** permission.
3. Add it to `Irfanwani/oriel` under **Settings → Secrets and variables → Actions** as `TAP_TOKEN`.

If the token is missing or rejected, the release still succeeds and the tap's scheduled `Update cask` workflow mirrors the release within an hour.

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

4. Commit the version bump and push `main`:

   ```sh
   git push origin main
   ```

5. Watch the workflow chain in the Actions tab:
   - **Test** builds and verifies the app.
   - **Auto release** runs after a successful Test. It reads `CFBundleShortVersionString`, checks that the tested commit is still the head of `main`, creates the matching `vX.Y.Z` tag, and dispatches **Release**.
   - **Release** checks that the tag matches `Resources/Info.plist`, builds the universal DMG, and publishes the GitHub Release.
   - **Update cask** audits and installs the new cask, then commits the version and SHA256 to the tap.

6. Confirm the new version installs:

   ```sh
   brew update
   brew upgrade --cask irfanwani/oriel/oriel
   oriel version
   ```

No manual tag is required. If the version tag and release already exist, or the tested commit is no longer the head of `main`, **Auto release** exits successfully without changing anything.

## Manual releases and retries

A manually pushed tag is still supported, as long as the tag matches `Resources/Info.plist`:

```sh
git tag -a v1.1.0 -m "Oriel 1.1.0"
git push origin v1.1.0
```

- If **Auto release** failed before creating the tag, run it manually from **Actions → Auto release → Run workflow** on `main`.
- If the tag exists but the release is missing or failed, run the release workflow on that tag:

  ```sh
  gh workflow run release.yml --ref v1.1.0
  ```

- Re-running **Release** for an already published tag is a no-op; it will not rebuild or replace release assets.

## Homebrew tap maintenance

The tap lives at [Irfanwani/homebrew-oriel](https://github.com/Irfanwani/homebrew-oriel).

Manual update from the tap checkout:

```sh
./scripts/update-cask.sh          # latest stable release
./scripts/update-cask.sh v1.1.0   # a specific tag
```

The updater reads the release SHA256, validates it against `Oriel-<version>.dmg.sha256`, and only changes the cask when needed. After a manual edit to the cask, run the **Test cask** workflow or push normally; that workflow audits and installs the cask.

If an automatic update commits with the tap's `GITHUB_TOKEN`, GitHub does not start another workflow from that push. That is why the updater audits and installs the new cask in the same run before committing.

## Rolling back a cask

Point the cask at the previous version manually or run:

```sh
./scripts/update-cask.sh v1.0.0
```

Only tags with a published `Oriel-<version>.dmg` and matching `.sha256` asset will update successfully.
