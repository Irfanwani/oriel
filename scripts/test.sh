#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Command Line Tools on recent macOS ship SwiftPM but not XCTest. Use Xcode's
# XCTest module and runner when they are available; a full Xcode install is the
# normal developer setup.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
XCODE="${XCODE_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
XCTEST_FRAMEWORKS="$XCODE/Platforms/MacOSX.platform/Developer/Library/Frameworks"
XCTEST_SWIFT_LIB="$XCODE/Platforms/MacOSX.platform/Developer/usr/lib"
XCTEST_RUNNER="$XCODE/usr/bin/xctest"

FLAGS=()
if [[ ! -d "/Library/Developer/CommandLineTools/Library/Developer/Frameworks/XCTest.framework" && \
      -d "$XCTEST_FRAMEWORKS/XCTest.framework" ]]; then
  FLAGS+=(
    -Xswiftc "-F$XCTEST_FRAMEWORKS"
    -Xswiftc "-I$XCTEST_SWIFT_LIB"
    -Xswiftc "-L$XCTEST_SWIFT_LIB"
    -Xswiftc -lXCTestSwiftSupport
    -Xlinker -rpath -Xlinker "$XCTEST_FRAMEWORKS"
    -Xlinker -rpath -Xlinker "$XCTEST_SWIFT_LIB"
  )
fi

# The Swift Build (XCBuild) backend currently needs an accepted Xcode license
# on CLT-only machines. Native SwiftPM has no such requirement here.
swift build --build-tests --build-system native "${FLAGS[@]}"

BUNDLE="$(find .build -type d -name 'OrielPackageTests.xctest' -print -quit)"
if [[ -z "$BUNDLE" ]]; then
  echo "✗ Could not find the built XCTest bundle." >&2
  exit 1
fi

if [[ -x "$XCTEST_RUNNER" ]]; then
  "$XCTEST_RUNNER" "$BUNDLE"
elif command -v xcrun >/dev/null 2>&1 && xcrun --find xctest >/dev/null 2>&1; then
  xcrun xctest "$BUNDLE"
else
  echo "✗ XCTest runner not found. Install Xcode to run the test suite." >&2
  exit 1
fi
