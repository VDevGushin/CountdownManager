#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

mode="${1:-full}"
capture_output_dir=""
case "$mode" in
    fast|ui|full|weather|empty-state|editor|desktop|attachments) ;;
    capture|weather-capture|empty-state-capture|compact-capture|completed-subtasks-capture|menu-identity-capture|automatic-title-capture|desktop-capture|attachments-capture)
        if [[ $# -ne 2 ]]; then
            echo "Usage: ./verify.sh $mode <marked-output-directory>" >&2
            exit 64
        fi
        capture_output_dir=$(cd "$2" && pwd -P)
        if [[ "$capture_output_dir" == "/" || ! -f "$capture_output_dir/.countdown-ui-capture-output" ]]; then
            echo "Capture output must be a marked directory containing .countdown-ui-capture-output" >&2
            exit 64
        fi
        ;;
    *)
        echo "Usage: ./verify.sh [fast|ui|full|weather|empty-state|editor|desktop|attachments|capture <directory>|weather-capture <directory>|empty-state-capture <directory>|compact-capture <directory>|completed-subtasks-capture <directory>|menu-identity-capture <directory>|automatic-title-capture <directory>|desktop-capture <directory>|attachments-capture <directory>]" >&2
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
fast_command=(swift run --disable-sandbox -c release --scratch-path "$scratch_path")
if [[ -n "${COUNTDOWN_SWIFTPM_CACHE_PATH:-}" ]]; then
    # Eval subjects have no network. Their runner prefetches into this local cache.
    fast_command+=(--build-system native --cache-path "$COUNTDOWN_SWIFTPM_CACHE_PATH" --skip-update --force-resolved-versions)
fi

run_fast_checks() {
    echo "Verification: native design source and build contract"
    python3 -B Tests/test_native_design_system.py
    python3 -B Tests/test_native_design_contract.py
    echo "Verification: CoreChecks"
    "${fast_command[@]}" CoreChecks
    echo "Verification: UIChecks"
    "${fast_command[@]}" UIChecks
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
    local timeout_seconds=45
    local launch_arguments=("$launch_argument")
    if [[ "$launch_argument" == "--ui-smoke-desktop" || "$launch_argument" == "--ui-smoke-menu-identity-captures" || "$launch_argument" == "--ui-smoke-attachment-preview" ]]; then timeout_seconds=70; fi
    if [[ "$launch_argument" == "--ui-smoke-attachment-preview" ]]; then
        launch_arguments=(--ui-smoke-desktop --ui-smoke-attachment-preview)
    fi
    mkdir -p "$test_home"
    touch "$test_home/.countdown-ui-smoke-environment"

    # AppKit must be registered through LaunchServices in the logged-in Aqua
    # session. Executing Contents/MacOS directly from this non-GUI shell aborts
    # in _RegisterApplication before applicationDidFinishLaunching can run.
    if ! /bin/launchctl print "gui/$(/usr/bin/id -u)" >/dev/null 2>&1; then
        echo "UISmoke requires a logged-in macOS Aqua session; gui/$(/usr/bin/id -u) is unavailable" >&2
        return 69
    fi
    if ! run_with_timeout "$timeout_seconds" /usr/bin/open -n -W \
        --env "COUNTDOWN_MANAGER_TEST_HOME=$test_home" \
        --stdout "$stdout_path" \
        --stderr "$stderr_path" \
        "$app_path" --args "${launch_arguments[@]}"; then
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

build_ui_app() {
    echo "Verification: release build"
    # Use the same verified native build path as delivered apps; do not prebuild via a
    # second toolchain/SDK route that may select different linked-on-or-after behavior.
    app_path="$verify_root/Countdown Manager.app"
    BUILD_DIR="$scratch_path" APP_OUTPUT_PATH="$app_path" COUNTDOWN_UPDATE_MODE=disabled \
        COUNTDOWN_UPDATE_FEED_URL= COUNTDOWN_UPDATE_PUBLIC_KEY= ./build.sh
}

run_ui_checks() {
    build_ui_app
    echo "Verification: full Real UI Smoke"
    run_smoke full-ui-smoke --ui-smoke
    echo "Verification: collapse/freeze regression"
    run_smoke collapse-regression --ui-smoke-collapse-regression
    echo "Verification: editor input, row deletion and weekday workflows"
    run_smoke editor-workflows --ui-smoke-editor-workflows
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
    local required_files=(
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
        12-today-badge \
        13-day-choices \
        14-day-editor \
        15-subtasks-reduced-motion-collapsed \
        16-nearest-today-without-icon \
        17-editor-dark-empty \
        18-editor-dark-selected \
        19-editor-dark-presets \
        20-editor-dark-catalogue \
        21-editor-light-empty \
        22-editor-light-selected \
        23-editor-light-presets \
        24-editor-light-catalogue \
        25-timer-completion-dark \
        26-timer-completion-light \
        27-timer-completion-dark-high-contrast \
        28-timer-completion-light-high-contrast \
        29-today-day-editor \
        30-settings-dark \
        31-settings-light
    )
    if [[ "$mode" == "weather-capture" ]]; then
        required_files=(weather-list-dark weather-list-light weather-list-light-high-contrast
                        weather-list-off-dark weather-settings-dark weather-settings-light
                        weather-editor-dark weather-editor-light
                        weather-header-before-midnight weather-header-midnight-empty)
    fi
    if [[ "$mode" == "empty-state-capture" ]]; then
        required_files=(empty-state-dark empty-state-light empty-state-light-high-contrast
                        empty-state-dark-reduced-motion empty-state-timer-running
                        empty-state-today-editor-dark empty-state-today-editor-light empty-state-midnight)
    fi
    if [[ "$mode" == "compact-capture" ]]; then
        required_files=(compact-cards-dark compact-cards-light compact-cards-high-contrast
                        compact-editor-dark compact-editor-light compact-editor-scroll compact-emoji compact-new-note-limit
                        compact-featured-today-dark compact-featured-today-light
                        compact-featured-no-weather-dark compact-featured-no-weather-light
                        compact-featured-long-dark compact-featured-long-light)
    fi
    if [[ "$mode" == "automatic-title-capture" ]]; then
        required_files=(automatic-title-auto-dark automatic-title-custom-dark
                        automatic-title-auto-light automatic-title-custom-light
                        automatic-title-auto-high-contrast automatic-title-custom-high-contrast)
    fi
    if [[ "$mode" == "completed-subtasks-capture" ]]; then
        required_files=()
        for appearance in dark light; do
            for state in complete partial zero; do
                for disclosure in expanded collapsed; do
                    required_files+=("completed-subtasks-$state-$disclosure-$appearance")
                done
            done
            required_files+=("completed-subtasks-empty-$appearance" "completed-subtasks-high-contrast-$appearance")
        done
    fi
    if [[ "$mode" == "menu-identity-capture" ]]; then
        required_files=()
        for appearance in light dark; do
            for state in finished mars-empty mars-unfavorited calendar-tomorrow calendar-today emoji-tomorrow running restored; do
                required_files+=("menu-$state-$appearance")
            done
            for state in empty unfavorited favorite; do
                required_files+=("identity-panel-$state-$appearance")
            done
            required_files+=("identity-app-icon-$appearance")
        done
    fi
    for required_file in "${required_files[@]}"; do
        [[ -s "$source_dir/$required_file.png" ]] || {
            echo "UISmoke capture is missing: $required_file.png" >&2
            return 1
        }
    done
    mkdir -p "$destination_dir"
    cp "$source_dir/manifest.json" "$destination_dir/"
    cp "$source_dir"/*.png "$destination_dir/"
    if [[ "$mode" == "compact-capture" ]]; then
        cp "$source_dir/compact-input-state.json" "$destination_dir/"
    fi
    if [[ "$mode" == "completed-subtasks-capture" || "$mode" == "menu-identity-capture" || "$mode" == "automatic-title-capture" ]]; then
        cp "$verify_root/visual-captures/ui-smoke-result.txt" "$destination_dir/"
        ditto "$app_path" "$destination_dir/Countdown Manager.app"
    fi
    echo "Capture evidence: $destination_dir"
}

run_capture_checks() {
    run_ui_checks
    echo "Verification: real panel capture evidence"
    run_smoke visual-captures --ui-smoke-captures
    copy_capture_evidence
}

case "$mode" in
    attachments|attachments-capture)
        build_ui_app
        run_smoke attachments-smoke --ui-smoke-attachment-preview
        if [[ "$mode" == "attachments-capture" ]]; then
            destination_dir="$capture_output_dir/countdown-attachments-captures-$(/bin/date +%Y%m%d-%H%M%S)-$$"
            test -s "$verify_root/attachments-smoke/Captures/manifest.json"
            mkdir "$destination_dir"
            cp "$verify_root/attachments-smoke/Captures/"*.png "$destination_dir/"
            cp "$verify_root/attachments-smoke/Captures/manifest.json" "$destination_dir/"
            cp "$verify_root/attachments-smoke/ui-smoke-result.txt" "$destination_dir/"
            ditto "$app_path" "$destination_dir/Countdown Manager.app"
            echo "Attachment evidence: $destination_dir"
        fi
        echo "PASS: native attachment shelves, libraries and quick preview workflows"
        ;;
    desktop|desktop-capture)
        build_ui_app
        run_smoke desktop-smoke --ui-smoke-desktop
        if [[ "$mode" == "desktop-capture" ]]; then
            destination_dir="$capture_output_dir/countdown-desktop-captures-$(/bin/date +%Y%m%d-%H%M%S)-$$"
            test -s "$verify_root/desktop-smoke/Captures/manifest.json"
            mkdir "$destination_dir"
            cp "$verify_root/desktop-smoke/Captures/"*.png "$destination_dir/"
            cp "$verify_root/desktop-smoke/Captures/manifest.json" "$destination_dir/"
            cp "$verify_root/desktop-smoke/ui-smoke-result.txt" "$destination_dir/"
            ditto "$app_path" "$destination_dir/Countdown Manager.app"
            echo "Desktop evidence: $destination_dir"
        fi
        echo "PASS: native desktop window and shared menu-panel workflows"
        ;;
    fast) run_fast_checks ;;
    ui) run_ui_checks ;;
    editor)
        build_ui_app
        run_smoke editor-workflows --ui-smoke-editor-workflows
        echo "PASS: focused editor input, row deletion and weekday workflows"
        ;;
    automatic-title-capture)
        build_ui_app
        run_smoke visual-captures --ui-smoke-automatic-title-captures
        copy_capture_evidence
        echo "PASS: automatic-title workflows and six native editor captures"
        ;;
    full)
        run_fast_checks
        run_ui_checks
        ;;
    capture)
        run_capture_checks
        ;;
    compact-capture)
        build_ui_app
        run_smoke visual-captures --ui-smoke-compact-captures
        copy_capture_evidence
        echo "PASS: focused compact cards and native note editing"
        ;;
    menu-identity-capture)
        build_ui_app
        run_smoke visual-captures --ui-smoke-menu-identity-captures
        copy_capture_evidence
        echo "PASS: focused native menu identity, transitions, status-only opening turn and24captures"
        ;;
    completed-subtasks-capture)
        build_ui_app
        run_smoke visual-captures --ui-smoke-completed-subtasks-captures
        copy_capture_evidence
        echo "PASS: focused completed-subtask indicator and16captures"
        ;;
    weather)
        build_ui_app
        run_smoke weather --ui-smoke-weather
        echo "PASS: focused weather Real UI Smoke"
        ;;
    weather-capture)
        build_ui_app
        run_smoke visual-captures --ui-smoke-weather-captures
        copy_capture_evidence
        echo "PASS: focused weather Real UI Smoke and ten captures"
        ;;
    empty-state|empty-state-capture)
        build_ui_app
        if [[ "$mode" == "empty-state-capture" ]]; then
            run_smoke visual-captures --ui-smoke-empty-state-captures
            copy_capture_evidence
        else
            run_smoke empty-state --ui-smoke-empty-state
        fi
        echo "PASS: focused empty-state Real UI Smoke"
        ;;
esac
