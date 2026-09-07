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

xcodebuild \
    -project CountdownManager.xcodeproj \
    -scheme CountdownManager \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    test
