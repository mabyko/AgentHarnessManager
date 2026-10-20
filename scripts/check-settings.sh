#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
settings_check_dir=$(mktemp -d /tmp/ahm-settings-check.XXXXXX)
trap 'rm -rf "$settings_check_dir"' EXIT
settings_check_app="$settings_check_dir/Check.app/Contents"
mkdir -p "$settings_check_app/MacOS" "$settings_check_app/Resources"
python3 - "$settings_check_app/Info.plist" <<'PY'
import plistlib
import sys
with open(sys.argv[1], "wb") as output:
    plistlib.dump({"CFBundleExecutable": "check", "CFBundleIdentifier": "local.ahm.settings-check", "CFBundlePackageType": "APPL"}, output)
PY
xcrun actool AgentHarnessManager/Assets.xcassets --compile "$settings_check_app/Resources" \
    --platform macosx --minimum-deployment-target 26.0 \
    --output-partial-info-plist "$settings_check_dir/assets.plist" --warnings --errors
swiftc -swift-version 6 -emit-module -emit-library -module-name SkillCore \
    Packages/SkillCore/Sources/SkillCore/*.swift \
    -emit-module-path "$settings_check_dir/SkillCore.swiftmodule" -o "$settings_check_dir/libSkillCore.dylib"
swiftc -swift-version 6 -I "$settings_check_dir" -L "$settings_check_dir" -lSkillCore \
    -Xlinker -rpath -Xlinker "$settings_check_dir" \
    AgentHarnessManager/AppStore.swift AgentHarnessManager/SettingsView.swift \
    AgentHarnessManager/AgentIntegrationSection.swift AgentHarnessManager/AgentIcon.swift \
    AgentHarnessManager/LibrarySidebar.swift AgentHarnessManager/Theme.swift \
    scripts/check-settings.swift -o "$settings_check_app/MacOS/check"
python3 - "$settings_check_app/MacOS/check" <<'PY'
import subprocess
import sys
import uuid
suite = "ahm.settings.check." + uuid.uuid4().hex
try:
    subprocess.run([sys.argv[1], suite], check=True, timeout=45)
finally:
    subprocess.run(["/usr/bin/defaults", "delete", suite], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
PY
