#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
APP="$BUILD_DIR/Oriel.app"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ARCH="${ARCH:-$(uname -m)}"

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  echo "→ Generating app icon"
  "$DEVELOPER_DIR/usr/bin/swift" "$ROOT/scripts/make-icon.swift"
fi

echo "→ Building Oriel $VERSION for $ARCH"
rm -rf "$APP" "$BUILD_DIR/.thin"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find "$ROOT/Sources" -name '*.swift' | sort)

EXTRA_FLAGS=()
if [[ "${DEBUG:-0}" == "1" ]]; then
  EXTRA_FLAGS+=("-Onone" "-g")
else
  EXTRA_FLAGS+=("-O")
fi

# SwiftUI ships its macros as a compiler-host plugin. The Command Line Tools
# installation does not include that plugin, so reuse the one from Xcode when
# it is available. Building with Xcode's full toolchain does not need this.
PLUGIN_FLAGS=()
XCODE_PLUGIN_DIR="$ROOT/.build-tools/plugins"
if [[ ! -d "$XCODE_PLUGIN_DIR" ]]; then
  XCODE_PLUGIN_DIR="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
fi
if [[ ! -f "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" && -f "$XCODE_PLUGIN_DIR/libSwiftUIMacros.dylib" ]]; then
  PLUGIN_FLAGS+=("-plugin-path" "$XCODE_PLUGIN_DIR")
fi

compile_arch() {
  local arch="$1"
  local output="$2"
  xcrun --sdk macosx swiftc \
    "${EXTRA_FLAGS[@]}" \
    "${PLUGIN_FLAGS[@]}" \
    -swift-version 5 \
    -target "$arch-apple-macos14.0" \
    -sdk "$SDK" \
    -module-name Oriel \
    -framework AppKit \
    -framework Carbon \
    -framework ServiceManagement \
    -o "$output" \
    "${SOURCES[@]}"
}

if [[ "$ARCH" == "universal" ]]; then
  THIN_DIR="$BUILD_DIR/.thin"
  mkdir -p "$THIN_DIR"
  echo "→ Compiling arm64"
  compile_arch arm64 "$THIN_DIR/Oriel-arm64"
  echo "→ Compiling x86_64"
  compile_arch x86_64 "$THIN_DIR/Oriel-x86_64"
  lipo -create "$THIN_DIR/Oriel-arm64" "$THIN_DIR/Oriel-x86_64" \
    -output "$APP/Contents/MacOS/Oriel"
  lipo -info "$APP/Contents/MacOS/Oriel"
else
  compile_arch "$ARCH" "$APP/Contents/MacOS/Oriel"
  file "$APP/Contents/MacOS/Oriel"
fi

if [[ -f "$ROOT/LICENSE" ]]; then
  cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
fi

# Ad-hoc signing keeps the app usable without a paid Apple Developer account.
# The signature changes with every build, so macOS may ask for Accessibility
# again after an update; the README explains the one-click fix.
if ! codesign --force --sign - --identifier app.oriel.mac "$APP" >/dev/null 2>&1; then
  echo "✗ Ad-hoc signing failed" >&2
  exit 1
fi
codesign --verify --deep --strict "$APP" >/dev/null 2>&1 || {
  echo "✗ Signature verification failed" >&2
  exit 1
}

echo "✓ Built $APP"
