#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [[ $# != 1 || "$1" != /* ]]; then
    printf 'Usage: scripts/prove-visual-foundation.sh /absolute/path/outside/repo\n' >&2
    exit 2
fi
proof_output="$1"
mkdir -p "$proof_output"
proof_output="$(cd "$proof_output" && pwd -P)"
if [[ "$proof_output" == "$repo_dir" || "$proof_output" == "$repo_dir/"* ]]; then
    printf 'Keep native proof images outside the Git checkout.\n' >&2
    exit 2
fi
build_dir="$repo_dir/.build/visual-foundation-proof"
bundle_dir="$build_dir/VisualProof.app"
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Resources"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
xcrun actool "$repo_dir/Resources/Assets.xcassets" --compile "$bundle_dir/Contents/Resources" \
    --platform macosx --target-device mac --minimum-deployment-target 14.0 \
    --output-format human-readable-text --notices --warnings --errors
xcrun swiftc -sdk "$sdk_path" -swift-version 6 -parse-as-library \
    -emit-module -emit-library -module-name MorningCore \
    "$repo_dir/Sources/MorningCore/MorningDayPhase.swift" \
    "$repo_dir/Sources/MorningCore/MorningCelestialPosition.swift" \
    -emit-module-path "$build_dir/MorningCore.swiftmodule" -o "$build_dir/libMorningCore.dylib"
xcrun swiftc -sdk "$sdk_path" -swift-version 6 -parse-as-library \
    -I "$build_dir" -L "$build_dir" -lMorningCore -Xlinker -rpath -Xlinker "$build_dir" \
    "$repo_dir/Sources/MorningOperator/MorningTheme.swift" \
    "$repo_dir/Sources/MorningOperator/MorningDottedArtwork.swift" \
    "$repo_dir/Sources/MorningOperator/MorningPaperSurface.swift" \
    "$repo_dir/Sources/MorningOperator/MorningSolarArtwork.swift" \
    "$repo_dir/scripts/proofs/MorningVisualFoundationProof.swift" \
    -o "$bundle_dir/Contents/MacOS/VisualProof"
cat > "$bundle_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>VisualProof</string><key>CFBundleIdentifier</key><string>local.more.visual-proof</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
"$bundle_dir/Contents/MacOS/VisualProof" "$proof_output"
