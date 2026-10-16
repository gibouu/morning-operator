#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
device_id=""
if [[ $# -gt 0 ]]; then
    [[ $# -eq 2 && "$1" == --install && -n "$2" ]] || { printf 'Usage: %s [--install DEVICE_ID]\n' "$0" >&2; exit 2; }
    device_id="$2"
fi
"$repo_dir/scripts/generate-jury-demo.sh"
derived_data="${MORE_DEMO_DERIVED_DATA:-$repo_dir/.build-jury-demo}"
mkdir -p "$derived_data"
destination='generic/platform=iOS'
[[ -z "$device_id" ]] || destination="platform=iOS,id=$device_id"
build_log="$derived_data/build.log"
demo_swift_flags='$(inherited) -j1'
if ! xcodebuild -quiet -jobs "${MORE_DEMO_JOBS:-2}" -project "$repo_dir/MorningOperatorDemo.xcodeproj" \
    -scheme MorningOperatorDemo -configuration Debug -destination "$destination" \
    -derivedDataPath "$derived_data" "OTHER_SWIFT_FLAGS=$demo_swift_flags" -allowProvisioningUpdates build >"$build_log" 2>&1; then
    printf 'Demo build failed. Inspect the local log: %s\n' "$build_log" >&2
    exit 1
fi
app_path="$derived_data/Build/Products/Debug-iphoneos/MorningOperatorDemo.app"
bundle_id="$(python3 - "$app_path" <<'PY'
import pathlib, plistlib, sys
def require(condition, message):
    if not condition:
        raise SystemExit(message)
app = pathlib.Path(sys.argv[1])
with (app/'Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
bundle = info['CFBundleIdentifier']
require(bundle != 'com.gibouu.morningoperator', 'Refusing to overwrite normal MORE')
require('demo' in bundle.lower().split('.'), 'Demo identifier must contain a demo component')
require(info['CFBundleDisplayName'] == 'MORE', 'Unexpected app name')
require(info.get('MorningJuryDemo') is True, 'Not a jury demo app')
require(info['MorningURLScheme'] == 'more-demo', 'Unexpected deep link')
widgets = list((app/'PlugIns').glob('*.appex'))
require(len(widgets) == 1, 'Expected the demo Live Activity widget')
with (widgets[0]/'Info.plist').open('rb') as stream:
    widget = plistlib.load(stream)
require(widget['CFBundleIdentifier'] == bundle + '.liveactivity', 'Widget identity is not isolated')
require(widget['MorningURLScheme'] == 'more-demo', 'Widget links to the wrong app')
print(bundle)
PY
)"
printf 'Built isolated app: %s\n' "$app_path"
if [[ -n "$device_id" ]]; then
    xcrun devicectl device install app --device "$device_id" "$app_path"
    xcrun devicectl device process launch --device "$device_id" "$bundle_id"
    printf 'Installed and launched %s; no app was uninstalled.\n' "$bundle_id"
fi
