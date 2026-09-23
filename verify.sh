#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

mode="${1:-full}"
capture_output_dir=""
case "$mode" in
    fast|ui|full) ;;
    capture)
        if [[ $# -ne 2 ]]; then
            echo "Usage: ./verify.sh capture <marked-output-directory>" >&2
            exit 64
        fi
        capture_output_dir=$(cd "$2" && pwd -P)
        if [[ "$capture_output_dir" == "/" || ! -f "$capture_output_dir/.countdown-ui-capture-output" ]]; then
            echo "Capture output must be a marked directory containing .countdown-ui-capture-output" >&2
            exit 64
        fi
        ;;
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
app_path=""

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
    local result_path="$test_home/ui-smoke-result.txt"
    local stdout_path="$test_home/ui-smoke.stdout"
    local stderr_path="$test_home/ui-smoke.stderr"
    mkdir -p "$test_home"
    touch "$test_home/.countdown-ui-smoke-environment"

    # AppKit must be registered through LaunchServices in the logged-in Aqua
    # session. Executing Contents/MacOS directly from this non-GUI shell aborts
    # in _RegisterApplication before applicationDidFinishLaunching can run.
    if ! /bin/launchctl print "gui/$(/usr/bin/id -u)" >/dev/null 2>&1; then
        echo "UISmoke requires a logged-in macOS Aqua session; gui/$(/usr/bin/id -u) is unavailable" >&2
        return 69
    fi
    if ! run_with_timeout 45 /usr/bin/open -n -W \
        --env "COUNTDOWN_MANAGER_TEST_HOME=$test_home" \
        --stdout "$stdout_path" \
        --stderr "$stderr_path" \
        "$app_path" --args "$launch_argument"; then
        echo "UISmoke could not launch through LaunchServices. Run it from a normal logged-in Aqua session, not a restricted shell." >&2
        [[ -f "$stderr_path" ]] && /bin/cat "$stderr_path" >&2
        return 69
    fi

    if [[ ! -f "$result_path" ]]; then
        echo "UISmoke did not write a result; stderr: $stderr_path" >&2
        [[ -f "$stderr_path" ]] && /bin/cat "$stderr_path" >&2
        return 1
    fi
    if ! /usr/bin/grep -q '^PASS:' "$result_path"; then
        echo "UISmoke failed; result: $result_path" >&2
        /bin/cat "$result_path" >&2
        return 1
    fi
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
    app_path="$verify_root/Countdown Manager.app"
    mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
    cp "$bin_path/CountdownManager" "$app_path/Contents/MacOS/CountdownManager"
    cp Resources/Info.plist "$app_path/Contents/Info.plist"
    cp Resources/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
    cp Resources/TimerFinished.mp3 "$app_path/Contents/Resources/TimerFinished.mp3"
    /usr/bin/codesign --force --sign - "$app_path"
    /usr/bin/codesign --verify --deep --strict "$app_path"
    echo "Verification: full Real UI Smoke"
    run_smoke full-ui-smoke --ui-smoke
    echo "Verification: collapse/freeze regression"
    run_smoke collapse-regression --ui-smoke-collapse-regression
    for run in 1 2 3; do
        echo "Verification: window/editor/list continuity regression (${run}/3)"
        run_smoke "editor-scroll-regression-$run" --ui-smoke-editor-scroll-regression
    done
    echo "PASS: release build and Real UI Smoke"
}

copy_capture_evidence() {
    local source_dir="$verify_root/visual-captures/Captures"
    local destination_dir="$capture_output_dir/countdown-ui-captures-$(/bin/date +%Y%m%d-%H%M%S)-$$"
    local required_file
    [[ -s "$source_dir/manifest.json" ]] || {
        echo "UISmoke capture manifest is missing" >&2
        return 1
    }
    for required_file in \
        01-idle-list \
        02-promoted-settled \
        03-timer-running \
        04-editor \
        05-timer-finished \
        06-empty \
        07-light-list \
        08-light-high-contrast \
        09-reduce-motion-running \
        10-timer-preset-120-static \
        11-timer-preset-reduced-motion-5-static \
        12-today-badge; do
        [[ -s "$source_dir/$required_file.png" ]] || {
            echo "UISmoke capture is missing: $required_file.png" >&2
            return 1
        }
    done
    mkdir -p "$destination_dir"
    cp "$source_dir/manifest.json" "$destination_dir/"
    cp "$source_dir"/*.png "$destination_dir/"
    echo "Capture evidence: $destination_dir"
}

run_capture_checks() {
    run_ui_checks
    echo "Verification: real panel capture evidence"
    run_smoke visual-captures --ui-smoke-captures
    copy_capture_evidence
}

case "$mode" in
    fast) run_fast_checks ;;
    ui) run_ui_checks ;;
    full)
        run_fast_checks
        run_ui_checks
        ;;
    capture)
        run_capture_checks
        ;;
esac
