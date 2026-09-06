#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

mode="${1:-full}"
case "$mode" in
    fast|ui|full) ;;
    *)
        echo "Usage: ./verify.sh [fast|ui|full]" >&2
        exit 64
        ;;
esac

verify_root=$(mktemp -d /private/tmp/countdown-verify.XXXXXX)
cleanup() {
    case "$verify_root" in
        /private/tmp/countdown-verify.*) rm -rf -- "$verify_root" ;;
        *) echo "Refusing to remove unexpected verification path: $verify_root" >&2 ;;
    esac
}
trap cleanup EXIT INT TERM

if [[ -z "${SDKROOT:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
fi
export CLANG_MODULE_CACHE_PATH="$verify_root/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$verify_root/swift-module-cache"

scratch_path="$verify_root/build"

run_fast_checks() {
    echo "Verification: CoreChecks"
    swift run --disable-sandbox -c release --scratch-path "$scratch_path" CoreChecks
    echo "Verification: UIChecks"
    swift run --disable-sandbox -c release --scratch-path "$scratch_path" UIChecks
}

run_with_timeout() {
    local timeout_seconds=$1
    shift
    "$@" &
    local test_pid=$!
    local started_at=$SECONDS
    while kill -0 "$test_pid" 2>/dev/null; do
        if (( SECONDS - started_at >= timeout_seconds )); then
            echo "UISmoke timed out after ${timeout_seconds}s" >&2
            kill -TERM "$test_pid" 2>/dev/null || true
            sleep 1
            kill -KILL "$test_pid" 2>/dev/null || true
            wait "$test_pid" 2>/dev/null || true
            return 124
        fi
        sleep 0.1
    done
    wait "$test_pid"
}

run_smoke() {
    local label=$1
    local launch_argument=$2
    local test_home="$verify_root/$label"
    mkdir -p "$test_home"
    touch "$test_home/.countdown-ui-smoke-environment"
    run_with_timeout 45 /usr/bin/env \
        COUNTDOWN_MANAGER_TEST_HOME="$test_home" \
        "$app_executable" "$launch_argument"
    local log_path="$test_home/Application Support/CountdownManager/Logs/countdown.log"
    if [[ -f "$log_path" ]] && /usr/bin/grep -q 'ui\.stall' "$log_path"; then
        echo "UISmoke detected a main-thread stall; log: $log_path" >&2
        return 1
    fi
}

run_ui_checks() {
    echo "Verification: release build"
    swift build --disable-sandbox -c release --scratch-path "$scratch_path"
    local bin_path
    bin_path=$(swift build --disable-sandbox -c release --scratch-path "$scratch_path" --show-bin-path)
    local app_path="$verify_root/Countdown Manager.app"
    mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
    cp "$bin_path/CountdownManager" "$app_path/Contents/MacOS/CountdownManager"
    cp Resources/Info.plist "$app_path/Contents/Info.plist"
    /usr/bin/codesign --force --sign - "$app_path"
    /usr/bin/codesign --verify --deep --strict "$app_path"
    app_executable="$app_path/Contents/MacOS/CountdownManager"
    echo "Verification: full Real UI Smoke"
    run_smoke full-ui-smoke --ui-smoke
    echo "Verification: collapse/freeze regression"
    run_smoke collapse-regression --ui-smoke-collapse-regression
    echo "PASS: release build and Real UI Smoke"
}

case "$mode" in
    fast) run_fast_checks ;;
    ui) run_ui_checks ;;
    full)
        run_fast_checks
        run_ui_checks
        ;;
esac
