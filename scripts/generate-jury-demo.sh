#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v xcodegen >/dev/null 2>&1 || { printf 'XcodeGen is required.\n' >&2; exit 2; }
normal_inputs=("$repo_dir/project.yml" "$repo_dir/Configuration/iOS-Info.plist" "$repo_dir/Configuration/ActivityWidget-Info.plist" "$repo_dir/MorningOperator.xcodeproj/project.pbxproj")
normal_before="$(shasum -a 256 "${normal_inputs[@]}")"
plutil -lint "$repo_dir/Configuration/JuryDemo-Info.plist" "$repo_dir/Configuration/JuryDemoActivityWidget-Info.plist" >/dev/null
xcodegen generate --spec "$repo_dir/project.demo.yml" --project "$repo_dir"
resolved_file="project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
[[ -f "$repo_dir/MorningOperator.xcodeproj/$resolved_file" ]] || { printf 'Generate the ordinary project with its committed package lock first.\n' >&2; exit 2; }
mkdir -p "$(dirname "$repo_dir/MorningOperatorDemo.xcodeproj/$resolved_file")"
cp "$repo_dir/MorningOperator.xcodeproj/$resolved_file" "$repo_dir/MorningOperatorDemo.xcodeproj/$resolved_file"
[[ "$normal_before" == "$(shasum -a 256 "${normal_inputs[@]}")" ]] || { printf 'Generation unexpectedly changed the normal app.\n' >&2; exit 2; }
python3 - "$repo_dir" <<'PY'
import json, pathlib, plistlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
def spec(path):
    return json.loads(subprocess.check_output(['xcodegen', 'dump', '--no-env', '--spec', str(root/path), '--type', 'json']))
normal_spec, demo_spec = spec('project.yml'), spec('project.demo.yml')
expected_sources = normal_spec['targets']['MorningOperator']['sources']
expected_sources = [dict(source, path='Configuration/JuryDemoResources/InfoPlist.xcstrings') if source['path'] == 'Resources/InfoPlist.xcstrings' else source for source in expected_sources]
assert demo_spec['targets']['MorningOperator']['sources'] == expected_sources, 'Keep demo app sources aligned with project.yml'
assert list(demo_spec['schemes']) == ['MorningOperatorDemo']
project = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(root/'MorningOperatorDemo.xcodeproj/project.pbxproj')]))
objects = project['objects']
targets = {value['name']: value for value in objects.values() if value.get('isa') == 'PBXNativeTarget'}
for name, plist, suffix in [('MorningOperator', 'JuryDemo-Info.plist', ''), ('MorningActivityWidget', 'JuryDemoActivityWidget-Info.plist', '.liveactivity')]:
    configurations = objects[targets[name]['buildConfigurationList']]['buildConfigurations']
    for configuration in configurations:
        settings = objects[configuration]['buildSettings']
        assert settings['INFOPLIST_FILE'] == 'Configuration/' + plist
        assert settings['PRODUCT_BUNDLE_IDENTIFIER'] == '$(MORE_DEMO_BUNDLE_IDENTIFIER)' + suffix
        assert 'MORE_JURY_DEMO' in settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']
with (root/'Configuration/JuryDemo-Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
assert info['MorningURLScheme'] == 'more-demo'
assert info['CFBundleDisplayName'] == 'MORE'
assert 'audio' in info['UIBackgroundModes']
assert info['NSAppTransportSecurity'] == {'NSAllowsLocalNetworking': True}
assert info['MorningJuryDemoBaseURL'] == '$(MORE_JURY_DEMO_BASE_URL)'
PY
printf 'Generated isolated MorningOperatorDemo.xcodeproj; normal project and plists unchanged.\n'
