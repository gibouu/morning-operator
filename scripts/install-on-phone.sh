#!/bin/bash
# Build the ordinary MORE app, sign it with your own team and install it on your iPhone.
# Nothing here is committed: the project is generated into a temporary folder, so your
# team and bundle prefix never reach MorningOperator.xcodeproj or Git.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
team_id="${DEVELOPMENT_TEAM:-}"
device_id=""
prefix="com.gibouu.morningoperator"
restricted="1"

usage() {
    cat <<'USAGE'
Usage: scripts/install-on-phone.sh --team TEAM_ID [--device DEVICE_ID] [--prefix BUNDLE_PREFIX] [--basic]

  --team TEAM_ID       Your 10-character Apple team ID (Xcode → Settings → Accounts).
  --device DEVICE_ID   The connected iPhone. Without it, the connected devices are listed.
  --prefix PREFIX      Bundle identifier prefix. Default: com.gibouu.morningoperator.
                       Use your own, e.g. com.yourname.morningoperator, if that one
                       belongs to another team.
  --basic              Sign without WeatherKit and Screen Time (Family Controls), for a
                       team that doesn't have them. Weather and Screen Time then show
                       as unavailable; everything else works.

The phone must be unlocked, connected (cable or same Wi-Fi) and in Developer Mode.
USAGE
}

value_after() { [[ $# -ge 2 && -n "$2" ]] || { printf 'Missing value for %s\n' "$1" >&2; exit 2; }; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --team) value_after "$@"; team_id="$2"; shift 2 ;;
        --device) value_after "$@"; device_id="$2"; shift 2 ;;
        --prefix) value_after "$@"; prefix="$2"; shift 2 ;;
        --basic) restricted="0"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] || { printf 'Supply your 10-character team ID with --team.\n' >&2; usage >&2; exit 2; }
[[ "$prefix" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || { printf 'Invalid bundle prefix.\n' >&2; exit 2; }
command -v xcodegen >/dev/null 2>&1 || { printf 'XcodeGen is required: brew install xcodegen\n' >&2; exit 2; }
if [[ -z "$device_id" ]]; then
    printf 'Connected devices (use the Identifier with --device):\n'
    xcrun devicectl list devices
    exit 2
fi
[[ "$device_id" =~ ^[A-Za-z0-9-]+$ ]] || { printf 'Invalid device identifier.\n' >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Same spec, your bundle prefix; generated outside the repository.
sed "s/com\.gibouu\.morningoperator/${prefix}/g" "$repo_dir/project.yml" > "$work/project.yml"
xcodegen generate --spec "$work/project.yml" --project "$work" --project-root "$repo_dir" >/dev/null

overrides=(DEVELOPMENT_TEAM="$team_id" CODE_SIGN_STYLE=Automatic)
[[ "$restricted" == "1" ]] || overrides+=(CODE_SIGN_ENTITLEMENTS=)
# Gmail sign-in uses your local Google iOS client, never stored here. Its bundle ID must match --prefix.
[[ -z "${MORE_GOOGLE_CLIENT_ID:-}" ]] || overrides+=(MORE_GOOGLE_CLIENT_ID="$MORE_GOOGLE_CLIENT_ID")
[[ -z "${MORE_GOOGLE_CALLBACK_SCHEME:-}" ]] || overrides+=(MORE_GOOGLE_CALLBACK_SCHEME="$MORE_GOOGLE_CALLBACK_SCHEME")

printf 'Building MORE for %s…\n' "$device_id"
xcodebuild -project "$work/MorningOperator.xcodeproj" -scheme MorningOperator -configuration Debug \
    -destination "id=$device_id" -derivedDataPath "$work/build" -allowProvisioningUpdates \
    "${overrides[@]}" build -quiet

app="$(find "$work/build/Build/Products" -maxdepth 2 -name 'MorningOperator.app' -type d | head -n 1)"
[[ -n "$app" ]] || { printf 'The build finished without an app.\n' >&2; exit 1; }
printf 'Installing…\n'
xcrun devicectl device install app --device "$device_id" "$app"
xcrun devicectl device process launch --device "$device_id" "$prefix" || \
    printf 'Installed. Open MORE on the phone (first time: Settings → General → VPN & Device Management → trust your developer certificate).\n'
