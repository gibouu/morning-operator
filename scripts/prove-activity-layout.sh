#!/bin/bash
set -euo pipefail

# Native macOS component proof. This neither installs an app nor starts ActivityKit.
# Optional MO_ACTIVITY_PROOF_CASES selects comma-separated named cases; default all.
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [[ $# != 1 || "$1" != /* ]]; then
    printf 'Usage: scripts/prove-activity-layout.sh /absolute/path/outside/repo\n' >&2
    exit 2
fi
mkdir -p "$1"
proof_output="$(cd "$1" && pwd -P)"
if [[ "$proof_output" == "$repo_dir" || "$proof_output" == "$repo_dir/"* ]]; then
    printf 'Keep proof images outside the Git checkout.\n' >&2
    exit 2
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
build_dir="$repo_dir/.build/activity-layout-proof"
package_dir="$build_dir/package"
products_dir="$package_dir/out/Products/Debug"
bundle_dir="$build_dir/ActivityLayoutProof.app"
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Resources"

# Swift Build compiles the actual MorningCore catalogs rather than copying keys.
# This isolated scratch directory does not contend with scripts/test.sh's build.
cd "$repo_dir"
xcrun swift build --disable-sandbox --build-system swiftbuild --target MorningCore \
    --scratch-path "$package_dir"
core_objects=()
while IFS= read -r object; do core_objects+=("$object"); done < <(
    rg --files --hidden --no-ignore "$package_dir/out/Intermediates.noindex" | \
        rg '/MorningCore-t\.build/Objects-normal/[^/]+/[^/]+\.o$' | sort
)
if [[ ${#core_objects[@]} == 0 ]]; then
    printf 'MorningCore object files are missing from the Swift Build output.\n' >&2
    exit 1
fi
cp -R "$products_dir/MorningOperator_MorningCore.bundle" "$bundle_dir/Contents/Resources/"
xcrun xcstringstool compile "$repo_dir/Sources/MorningActivityWidget/Localizable.xcstrings" \
    --output-directory "$bundle_dir/Contents/Resources"
production_sources=(
    "$repo_dir/Sources/MorningActivityWidget/MorningActivityWidget.swift"
    "$repo_dir/Sources/MorningSharedActivity/MorningBrandView.swift"
    "$repo_dir/Sources/MorningCore/MorningBrand.swift"
)
production_sha="$(cat "${production_sources[@]}" | shasum -a 256 | cut -d ' ' -f 1)"
proof_output_base="$proof_output"
proof_run="$(date -u +%Y%m%dT%H%M%SZ)-$$"
proof_output="$proof_output_base/$production_sha/$proof_run"
mkdir -p "$proof_output"

# Copy the production private views, freeze only the native date providers, then
# append the proof in the same Swift file. The process-bound intent and its remote
# action host are inert stubs; every production label/layout modifier is unchanged.
python3 - "$repo_dir" "$build_dir/ActivityLayoutProof.swift" <<'PY'
from pathlib import Path
import sys
repo, output = map(Path, sys.argv[1:])
source = (repo / 'Sources/MorningActivityWidget/MorningActivityWidget.swift').read_text()
brand_views = (repo / 'Sources/MorningSharedActivity/MorningBrandView.swift').read_text()
marker = 'private struct MorningActivityIslandDetail: View {'
if source.count(marker) != 1:
    raise SystemExit('Expected exactly one production island detail view.')
production = source[source.index(marker):]
# Freeze only the native date providers: ImageRenderer cannot take a coherent
# offscreen snapshot while those providers invalidate. Keep all fonts, labels,
# layout, frames, margins and accessibility modifiers verbatim.
clock = 'Text(timerInterval: min(state.updatedAt, timer.endsAt)...timer.endsAt, countsDown: true)'
progress = 'ProgressView(timerInterval: start...timer.endsAt, countsDown: false)'
if production.count(clock) != 1 or production.count(progress) != 1:
    raise SystemExit('Production clock/progress providers changed; review the proof adapters.')
production = production.replace(clock, 'Text(proofFrozenCountdown(timer: timer, state: state))')
production = production.replace(progress, 'ProgressView(value: timer.elapsedFraction(at: state.updatedAt) ?? 0)')
output.write_text('import AppKit\nimport AppIntents\nimport Foundation\nimport MorningCore\nimport SwiftUI\nimport Vision\n\n' + brand_views + '\n' + production + '\n' + (repo / 'scripts/proofs/MorningActivityLayoutProof.swift').read_text())
PY
xcrun swiftc -sdk "$SDKROOT" -swift-version 6 -parse-as-library \
    -I "$products_dir" "${core_objects[@]}" "$build_dir/ActivityLayoutProof.swift" \
    -o "$bundle_dir/Contents/MacOS/ActivityLayoutProof"
cat > "$bundle_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>ActivityLayoutProof</string><key>CFBundleIdentifier</key><string>local.more.activity-layout-proof</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleDevelopmentRegion</key><string>en</string></dict></plist>
PLIST
shasum -a 256 "${production_sources[@]}" \
    > "$proof_output/production-source.sha256"
"$bundle_dir/Contents/MacOS/ActivityLayoutProof" "$proof_output"
ln -sfn "$production_sha/$proof_run" "$proof_output_base/latest"
