#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD_DIR="${BUILD_DIR:-$PWD/.build}"
swift build -c release --scratch-path "$BUILD_DIR"
BIN_DIR="$(swift build -c release --scratch-path "$BUILD_DIR" --show-bin-path)"
APP="$PWD/Countdown Manager.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CountdownManager" "$APP/Contents/MacOS/CountdownManager"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Готово: $APP"
