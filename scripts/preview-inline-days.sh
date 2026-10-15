#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -lt 1 ]]; then
    printf 'Usage: scripts/preview-inline-days.sh OUTPUT_DIRECTORY [--interactive]\n' >&2
    exit 2
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
proof_dir="$repo_dir/work/inline-day-proof"
mkdir -p "$proof_dir"
# A separate scratch path avoids racing the package test runner.
xcrun swift build --package-path "$repo_dir" --scratch-path "$proof_dir/package" \
    --disable-sandbox --build-system swiftbuild --product MorningCore > "$proof_dir/core-build.log" 2>&1
products="$proof_dir/package/out/Products/Debug"
if [[ ! -d "$products" ]]; then products="$proof_dir/package/Products/Debug"; fi
xcrun swiftc -parse-as-library -I "$products" -L "$products" -lMorningCore \
    "$repo_dir/Sources/MorningOperator/MorningInlineDayStrip.swift" \
    "$repo_dir/scripts/preview-inline-days.swift" -o "$proof_dir/inline-day-proof"
"$proof_dir/inline-day-proof" "$@"
