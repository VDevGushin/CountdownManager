#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

derived_data=$(mktemp -d /private/tmp/countdown-xcui-derived.XXXXXX)
cleanup() {
    case "$derived_data" in
        /private/tmp/countdown-xcui-derived.*) rm -rf -- "$derived_data" ;;
        *) echo "Refusing to remove unexpected XCUITest path: $derived_data" >&2 ;;
    esac
}
trap cleanup EXIT INT TERM

bundle_identifier="local.countdownmanager.ui-test"
build_settings=(
    -project CountdownManager.xcodeproj \
    -scheme CountdownManager \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    COUNTDOWN_APP_BUNDLE_IDENTIFIER="$bundle_identifier"
)
xcodebuild "${build_settings[@]}" build-for-testing
target_info="$derived_data/Build/Products/Debug/Countdown Manager.app/Contents/Info.plist"
actual_identifier=$(/usr/bin/plutil -extract CFBundleIdentifier raw "$target_info")
if [[ "$actual_identifier" != "$bundle_identifier" ]]; then
    echo "Refusing to run XCUITest without its separate application bundle identifier" >&2
    exit 64
fi
xcodebuild "${build_settings[@]}" "$@" test-without-building
