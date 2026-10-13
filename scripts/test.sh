#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
with_model="0"
# Keep this array nonempty for the system Bash 3.2's nounset behavior.
test_options=(--disable-sandbox --disable-xctest)
while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-model) with_model="1"; shift ;;
        --help|-h)
            cat <<'USAGE'
Usage: scripts/test.sh [--with-model] [swift test options...]

Runs the local Swift Testing suites with the selected Apple toolchain's default builder.
  --with-model        Also attempt the optional real on-device Foundation Models test.
  --filter PATTERN    Passed through to swift test (and other Swift test options likewise).

The script loads the toolchain's TestingMacros plugin if found, disables the XCTest
runner, and keeps build/cache files under .build/testing*. It runs only this local,
dependency-free package with the package sandbox disabled for CLT compatibility.
It does not install an iPhone app or run device/UI tests. Unavailable optional model
tests are skipped and must not be reported as passes.
USAGE
            exit 0
            ;;
        --) shift; test_options+=("$@"); break ;;
        *) test_options+=("$1"); shift ;;
    esac
done

swift_tool="$(xcrun --find swift)"
swift_compiler="$(xcrun --find swiftc)"
toolchain_usr="$(cd "$(dirname "$swift_compiler")/.." && pwd)"
developer_dir="$(xcode-select -p)"
plugin=""
for candidate in \
    "$toolchain_usr/lib/swift/host/plugins/testing/libTestingMacros.dylib" \
    "$developer_dir/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"; do
    if [[ -f "$candidate" ]]; then plugin="$candidate"; break; fi
done

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$repo_dir/.build/testing-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$repo_dir/.build/testing-module-cache}"
if [[ "$with_model" == "1" ]]; then export MO_RUN_MODEL_INTEGRATION=1; fi
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" "$repo_dir/.build/testing-cache"
if [[ -n "$plugin" ]]; then
    printf 'Using bundled Swift Testing macro plugin: %s\n' "$plugin"
    test_options+=(-Xswiftc -load-plugin-library -Xswiftc "$plugin")
else
    printf 'No separate TestingMacros plugin found; using toolchain automatic discovery.\n'
fi

# Ask for the Swift Build engine by name. Older toolchains default to the native
# engine, which copies Localizable.xcstrings into the bundle without compiling it:
# every lookup then returns its English key and French or plural checks prove nothing.
# The native engine in the observed CLT setup also could not resolve the Testing module.
# A caller may still pass its own --build-system. This package has no third-party plugins.
build_system_chosen="0"
for option in "${test_options[@]}"; do
    if [[ "$option" == "--build-system" || "$option" == --build-system=* ]]; then build_system_chosen="1"; fi
done
if [[ "$build_system_chosen" == "0" ]]; then test_options+=(--build-system swiftbuild); fi

cd "$repo_dir"
"$swift_tool" test \
    --scratch-path "$repo_dir/.build/testing" \
    --cache-path "$repo_dir/.build/testing-cache" \
    "${test_options[@]}"
