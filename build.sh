#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD_DIR="${BUILD_DIR:-$PWD/.build}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$BUILD_DIR/clang-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$BUILD_DIR/swift-module-cache}"
APP="${APP_OUTPUT_PATH:-$PWD/Countdown Manager.app}"
if [[ -n "${SDKROOT:-}" && "$SDKROOT" == /* ]]; then
    compiler_sdk="$SDKROOT"
else
    compiler_sdk="$(xcrun --sdk "${SDKROOT:-macosx}" --show-sdk-path)"
fi
export SDKROOT="$compiler_sdk"
swift_driver="$(xcrun --find swift)"
contract_link_flags="$(python3 scripts/native_design_contract.py linker-flags)"
IFS=' ' read -r -a contract_link_args <<< "$contract_link_flags"
build_args=(--build-system native --sdk "$compiler_sdk" --disable-sandbox -c release --scratch-path "$BUILD_DIR")
stage=$(mktemp -d "${TMPDIR:-/private/tmp}/countdown-bundle.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
staged_app="$stage/Countdown Manager.app"
python3 scripts/native_design_contract.py snapshot --compiler-sdk "$compiler_sdk" --swift "$swift_driver" \
    --output "$stage/native-build-context.json"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources" "$staged_app/Contents/Frameworks"
cp Resources/Info.plist "$staged_app/Contents/Info.plist"
python3 scripts/update_tools.py configure "$staged_app/Contents/Info.plist"
"$swift_driver" build "${build_args[@]}" "${contract_link_args[@]}" --product CountdownManager
BIN_DIR="$("$swift_driver" build "${build_args[@]}" "${contract_link_args[@]}" --show-bin-path)"
cp "$BIN_DIR/CountdownManager" "$staged_app/Contents/MacOS/CountdownManager"
cp Resources/AppIcon.icns "$staged_app/Contents/Resources/AppIcon.icns"
cp Resources/Assets.car "$staged_app/Contents/Resources/Assets.car"
cp Resources/MarsMenu.pdf Resources/CalendarMenu.pdf "$staged_app/Contents/Resources/"
cp Resources/MarsMenuLight.pdf Resources/MarsMenuDark.pdf "$staged_app/Contents/Resources/"
cp Resources/TimerFinished.mp3 "$staged_app/Contents/Resources/TimerFinished.mp3"
python3 scripts/native_design_contract.py record --app "$staged_app" --context "$stage/native-build-context.json"
python3 scripts/update_tools.py embed "$BUILD_DIR" "$staged_app"
python3 scripts/native_design_contract.py verify --app "$staged_app"
python3 scripts/update_tools.py install-built-bundle "$staged_app" "$APP"
echo "Готово: $APP"
