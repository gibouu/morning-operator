#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
device_id=""
team_id="${DEVELOPMENT_TEAM:-}"
suite="fixture"
external_bundle=""
navigation_label=""
expected_label=""
capture_tree="0"
general_label="General"
about_label="About"

usage() {
    cat <<'USAGE'
Usage: scripts/run-device-tests.sh --device DEVICE_ID --team TEAM_ID [options]

  --suite fixture|learning|recording|clock|settings|external
                                     Default: fixture (synthetic app data only).
                                     learning: local model with synthetic notes.
                                     recording: owner confirms Apple's capture picker.
                                     clock: read-only Clock tabs and list scroll.
  --external-bundle BUNDLE_ID         Required for the external capture suite.
  --navigate-label LABEL              Optional single read-only navigation step.
  --expect-label LABEL                Required new-screen postcondition for that step.
  --capture-ui-tree                   Also keep private accessibility text in xcresult.
  --general-label LABEL               Localized Settings General label.
  --about-label LABEL                 Localized Settings About label.
  --help                             Show this message without accessing a device.

External navigation labels: Inbox, All Inboxes, Mailboxes, Chats, Messages, Settings, About.
External-app checks do not type, send, delete, replay coordinates or retry automatically.
DEVELOPMENT_TEAM can supply the team instead of --team. No team is stored in the repo.
Screenshots/test results remain under work/device-runs and can contain personal content.
USAGE
}

value_after() {
    [[ $# -ge 2 && -n "$2" ]] || { printf 'Missing value for %s\n' "$1" >&2; exit 2; }
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --device) value_after "$@"; device_id="$2"; shift 2 ;;
        --team) value_after "$@"; team_id="$2"; shift 2 ;;
        --suite) value_after "$@"; suite="$2"; shift 2 ;;
        --external-bundle) value_after "$@"; external_bundle="$2"; shift 2 ;;
        --navigate-label) value_after "$@"; navigation_label="$2"; shift 2 ;;
        --expect-label) value_after "$@"; expected_label="$2"; shift 2 ;;
        --capture-ui-tree) capture_tree="1"; shift ;;
        --general-label) value_after "$@"; general_label="$2"; shift 2 ;;
        --about-label) value_after "$@"; about_label="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -n "$device_id" ]] || { printf 'Choose an explicit physical device with --device.\n' >&2; exit 2; }
[[ "$device_id" =~ ^[A-Za-z0-9-]+$ ]] || { printf 'Invalid device identifier.\n' >&2; exit 2; }
[[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] || { printf 'Supply your 10-character team identifier with --team or DEVELOPMENT_TEAM.\n' >&2; exit 2; }
case "$suite" in
    fixture) test_filters=("-only-testing:MorningOperatorUITests/FixtureJourneyTests") ;;
    learning) test_filters=("-only-testing:MorningOperatorUITests/OnDeviceLearningTests") ;;
    recording) test_filters=("-only-testing:MorningOperatorUITests/RecordingLearningTests") ;;
    clock) test_filters=("-only-testing:MorningOperatorUITests/ClockObservationTests/testClockTabsAndReadOnlyAlarmScroll") ;;
    settings) test_filters=(
        "-only-testing:MorningOperatorUITests/DeviceObservationTests/testSettingsReadOnlyNavigation"
        "-only-testing:MorningOperatorUITests/DeviceObservationTests/testMissingTargetDoesNotTriggerGesture"
        ) ;;
    external)
        test_filters=("-only-testing:MorningOperatorUITests/DeviceObservationTests/testExplicitExternalAppCaptureAndOptionalNavigation")
        [[ "$external_bundle" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || { printf 'Supply the actual installed app bundle ID.\n' >&2; exit 2; }
        ;;
    *) printf 'Unknown suite: %s\n' "$suite" >&2; exit 2 ;;
esac
if [[ -n "$navigation_label" || -n "$expected_label" ]]; then
    [[ "$suite" == "external" && -n "$navigation_label" && -n "$expected_label" ]] || { printf 'Navigation needs the external suite plus both labels.\n' >&2; exit 2; }
    case "$navigation_label" in
        Inbox|"All Inboxes"|Mailboxes|Chats|Messages|Settings|About) ;;
        *) printf 'Unsupported navigation label. No action will run.\n' >&2; exit 2 ;;
    esac
fi

command -v python3 >/dev/null 2>&1 || { printf 'Python 3 is required for the local test-run configuration.\n' >&2; exit 2; }
xcodebuild -version >/dev/null 2>&1 || { printf 'Full Xcode is required; run scripts/check-environment.sh.\n' >&2; exit 2; }
"$repo_dir/scripts/generate-project.sh"
run_dir="$repo_dir/work/device-runs/$(date -u +%Y%m%dT%H%M%SZ)-$$"
# Reuse the project's existing phone build products across suites and runs.
derived_dir="$repo_dir/.build/iphone"
mkdir -p "$run_dir"
printf 'Selected physical device: %s\nSuite: %s\nPrivate evidence: %s\n' "$device_id" "$suite" "$run_dir"

# No automatic provisioning update or device registration is requested here.
xcodebuild build-for-testing \
    -project "$repo_dir/MorningOperator.xcodeproj" \
    -scheme MorningOperator \
    -configuration Debug \
    -destination "platform=iOS,id=$device_id" \
    -derivedDataPath "$derived_dir" \
    -parallel-testing-enabled NO \
    "DEVELOPMENT_TEAM=$team_id" \
    >"$run_dir/build.log" 2>&1 || { printf 'Build failed; inspect %s/build.log\n' "$run_dir" >&2; exit 1; }

# xctestrun EnvironmentVariables reach the test runner; ordinary shell variables do not reliably do so.
# Keep the amended file beside the generated original so __TESTROOT__ stays correct.
xctestrun_path="$(python3 - "$derived_dir/Build/Products" "$suite" "$external_bundle" "$navigation_label" "$expected_label" "$capture_tree" "$general_label" "$about_label" <<'PY'
import pathlib, plistlib, sys
products = pathlib.Path(sys.argv[1])
candidates = sorted(path for path in products.glob('MorningOperator_*.xctestrun')
                    if 'configured' not in path.stem)
if len(candidates) != 1:
    raise SystemExit(f'Expected one xctestrun, found {len(candidates)}')
with candidates[0].open('rb') as stream:
    plan = plistlib.load(stream)
env = {
    'MO_DEVICE_TESTS_ENABLED': '1' if sys.argv[2] in ('settings', 'external') else '0',
    'MO_RECORDING_TEST_ENABLED': '1' if sys.argv[2] == 'recording' else '0',
    'MO_CLOCK_TEST_ENABLED': '1' if sys.argv[2] == 'clock' else '0',
    'MO_EXTERNAL_APP_BUNDLE_ID': sys.argv[3],
    'MO_EXTERNAL_NAVIGATION_LABEL': sys.argv[4],
    'MO_EXTERNAL_EXPECTED_LABEL': sys.argv[5],
    'MO_CAPTURE_UI_TREE': sys.argv[6],
    'MO_SETTINGS_GENERAL_LABEL': sys.argv[7],
    'MO_SETTINGS_ABOUT_LABEL': sys.argv[8],
}
if 'TestConfigurations' in plan:
    targets = [target for config in plan['TestConfigurations'] for target in config.get('TestTargets', [])]
else:
    targets = [value for key, value in plan.items() if key != '__xctestrun_metadata__' and isinstance(value, dict)]
matched = 0
for target in targets:
    if 'MorningOperatorUITests' in str(target.get('BlueprintName', '')) or 'MorningOperatorUITests' in str(target.get('TestBundlePath', '')):
        target.setdefault('EnvironmentVariables', {}).update(env)
        matched += 1
if matched != 1:
    raise SystemExit(f'Expected one UI test target, found {matched}')
output = products / 'MorningOperator-configured.xctestrun'
with output.open('wb') as stream:
    plistlib.dump(plan, stream)
print(output)
PY
)"

xcodebuild test-without-building \
    -xctestrun "$xctestrun_path" \
    -destination "platform=iOS,id=$device_id" \
    "${test_filters[@]}" \
    -parallel-testing-enabled NO \
    -resultBundlePath "$run_dir/Results.xcresult" \
    >"$run_dir/test.log" 2>&1 || { printf 'Test failed; inspect %s/test.log and Results.xcresult\n' "$run_dir" >&2; exit 1; }
printf 'Requested test execution finished. Inspect pass/skip status and evidence in %s/Results.xcresult\n' "$run_dir"
