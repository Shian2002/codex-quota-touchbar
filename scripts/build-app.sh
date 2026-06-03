#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build"
APP="$BUILD_DIR/CodexQuotaTouchBar.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

rm -rf "$APP"
mkdir -p "$MACOS"

swiftc \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target "$(uname -m)-apple-macos12.0" \
  -framework AppKit \
  "$ROOT"/Sources/*.swift \
  -o "$MACOS/CodexQuotaTouchBar"

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null
plutil -lint "$CONTENTS/Info.plist" >/dev/null
codesign --verify --deep --strict "$APP"

echo "$APP"
