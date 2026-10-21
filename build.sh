#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD_DIR="${BUILD_DIR:-$PWD/.build}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$BUILD_DIR/clang-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$BUILD_DIR/swift-module-cache}"
APP="${APP_OUTPUT_PATH:-$PWD/Countdown Manager.app}"
stage=$(mktemp -d "${TMPDIR:-/private/tmp}/countdown-bundle.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
staged_app="$stage/Countdown Manager.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources" "$staged_app/Contents/Frameworks"
cp Resources/Info.plist "$staged_app/Contents/Info.plist"
python3 scripts/update_tools.py configure "$staged_app/Contents/Info.plist"
swift build --disable-sandbox -c release --scratch-path "$BUILD_DIR" --product CountdownManager
BIN_DIR="$(swift build --disable-sandbox -c release --scratch-path "$BUILD_DIR" --show-bin-path)"
cp "$BIN_DIR/CountdownManager" "$staged_app/Contents/MacOS/CountdownManager"
cp Resources/AppIcon.icns "$staged_app/Contents/Resources/AppIcon.icns"
cp Resources/Assets.car "$staged_app/Contents/Resources/Assets.car"
cp Resources/MarsMenu.pdf Resources/CalendarMenu.pdf "$staged_app/Contents/Resources/"
cp Resources/MarsMenuLight.pdf Resources/MarsMenuDark.pdf "$staged_app/Contents/Resources/"
cp Resources/TimerFinished.mp3 "$staged_app/Contents/Resources/TimerFinished.mp3"
python3 scripts/update_tools.py embed "$BUILD_DIR" "$staged_app"
python3 scripts/update_tools.py install-built-bundle "$staged_app" "$APP"
echo "Готово: $APP"
