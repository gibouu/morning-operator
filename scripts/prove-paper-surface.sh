#!/bin/bash
set -euo pipefail

# Native macOS SwiftUI renders of the actual component. No app is installed.
# The output directory must be outside Git: screenshots are local review proof.
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# != 1 ]]; then
    printf 'Usage: scripts/prove-paper-surface.sh /absolute/path/outside/repo\n' >&2
    exit 2
fi
proof_output="$1"
if [[ "$proof_output" != /* ]]; then
    printf 'Choose an absolute output directory outside this Git checkout.\n' >&2
    exit 2
fi
mkdir -p "$proof_output"
proof_output="$(cd "$proof_output" && pwd -P)"
if [[ "$proof_output" == "$repo_dir" || "$proof_output" == "$repo_dir/"* ]]; then
    printf 'Choose an absolute output directory outside this Git checkout.\n' >&2
    exit 2
fi
build_dir="$repo_dir/.build/paper-surface-proof"
mkdir -p "$build_dir"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -sdk "$sdk_path" -swift-version 6 -parse-as-library \
    -emit-module -emit-library -module-name MorningCore \
    "$repo_dir/Sources/MorningCore/MorningDayPhase.swift" \
    "$repo_dir/Sources/MorningCore/MorningCelestialPosition.swift" \
    -emit-module-path "$build_dir/MorningCore.swiftmodule" \
    -o "$build_dir/libMorningCore.dylib"
xcrun swiftc -sdk "$sdk_path" -swift-version 6 -parse-as-library \
    -I "$build_dir" -L "$build_dir" -lMorningCore \
    -Xlinker -rpath -Xlinker "$build_dir" \
    "$repo_dir/Sources/MorningOperator/MorningTheme.swift" \
    "$repo_dir/Sources/MorningOperator/MorningDottedArtwork.swift" \
    "$repo_dir/Sources/MorningOperator/MorningPaperSurface.swift" \
    "$repo_dir/scripts/proofs/MorningPaperSurfaceProof.swift" \
    -o "$build_dir/paper-proof"
"$build_dir/paper-proof" "$proof_output"
