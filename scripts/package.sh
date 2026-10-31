#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ARCH="${ARCH:-universal}"
DIST="$ROOT/dist"
APP="$ROOT/build/Oriel.app"
DMG="$DIST/Oriel-$VERSION.dmg"
STAGE="$ROOT/build/dmg-stage"

echo "→ Building Oriel $VERSION ($BUILD_NUMBER, $ARCH)"
VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" ARCH="$ARCH" "$ROOT/scripts/build.sh"

codesign --verify --deep --strict "$APP"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE" "$DIST"
cp -R "$APP" "$STAGE/Oriel.app"
cp "$ROOT/scripts/oriel" "$STAGE/oriel"
chmod +x "$STAGE/oriel"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/LICENSE" "$STAGE/LICENSE.txt"
[ -f "$ROOT/README.md" ] && cp "$ROOT/README.md" "$STAGE/README.md"

# Homebrew recommends no resource forks in DMGs.
xattr -cr "$STAGE" 2>/dev/null || true
COPYFILE_DISABLE=1 hdiutil create \
  -volname "Oriel" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

hdiutil verify "$DMG" >/dev/null
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$DMG")" > "$DMG.sha256"

echo "✓ $DMG"
echo "  sha256 $SHA"
