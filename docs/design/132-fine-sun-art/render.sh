#!/bin/zsh
set -euo pipefail
MORE_SUN_SOURCE="${0:A:h}"
MORE_SUN_REPO="${MORE_SUN_SOURCE}/../../.."
MORE_SUN_OUT="${1:-${MORE_SUN_REPO}/.build/fine-sun-proof}"
MORE_SUN_BINARY="$(mktemp -t more-sun-proof)"
trap 'rm -f "$MORE_SUN_BINARY"' EXIT
mkdir -p "$MORE_SUN_OUT"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx26.0 \
  "$MORE_SUN_REPO/Sources/MorningOperator/MorningSolarArtwork.swift" \
  "$MORE_SUN_SOURCE/NativeSunProof.swift" -o "$MORE_SUN_BINARY"
"$MORE_SUN_BINARY" \
  "$MORE_SUN_REPO/Resources/Assets.xcassets/SolarSunFineV1.imageset/solar-sun-fine-v1.png" \
  "$MORE_SUN_OUT/sun-paper-compositing.png"
