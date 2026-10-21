#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
case "${1:-}" in
    "") settings_check_source=scripts/check-settings.swift ;;
    --accessibility) settings_check_source=scripts/check-accessibility.swift ;;
    --instructions) settings_check_source=scripts/check-instructions.swift ;;
    *) exit 64 ;;
esac
settings_check_dir=$(mktemp -d /tmp/ahm-settings-check.XXXXXX)
trap 'rm -rf "$settings_check_dir"' EXIT
settings_check_app="$settings_check_dir/Check.app/Contents"
mkdir -p "$settings_check_app/MacOS" "$settings_check_app/Resources"
python3 - "$settings_check_app/Info.plist" <<'PY'
import plistlib
import sys
import uuid
with open(sys.argv[1], "wb") as output:
    plistlib.dump({"CFBundleExecutable": "check", "CFBundleIdentifier": "local.ahm.settings-check." + uuid.uuid4().hex, "CFBundlePackageType": "APPL"}, output)
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
    AgentHarnessManager/ContentView.swift AgentHarnessManager/LibraryDetailViews.swift \
    AgentHarnessManager/GroupEditor.swift AgentHarnessManager/ProfilesView.swift \
    AgentHarnessManager/SourceEditorSheet.swift AgentHarnessManager/AgentRequestDetail.swift \
    AgentHarnessManager/InstructionStore.swift AgentHarnessManager/InstructionViews.swift \
    scripts/skill-update-fixture.swift "$settings_check_source" -o "$settings_check_app/MacOS/check"
python3 - "$settings_check_app/MacOS/check" <<'PY'
import subprocess
import sys
import uuid
import os
import signal
import shlex
import pathlib
suite = "ahm.settings.check." + uuid.uuid4().hex
process = None
try:
    process = subprocess.Popen([sys.argv[1], suite], start_new_session=True)
    if process.wait(timeout=45):
        raise RuntimeError("Native settings check failed")
finally:
    if process is not None:
        # Foundation Process can create a separate process group for the fixture.
        for row in subprocess.check_output(["/bin/ps", "-axo", "pid=,command="], text=True).splitlines():
            parts = row.strip().split(None, 1)
            if len(parts) != 2:
                continue
            try:
                arguments = shlex.split(parts[1])
            except ValueError:
                continue
            if arguments[:2] == [sys.argv[1], suite] and "--fixture" in arguments:
                try:
                    os.kill(int(parts[0]), signal.SIGTERM)
                except ProcessLookupError:
                    pass
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    subprocess.run(["/usr/bin/defaults", "delete", suite], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # Remove the fixture's own registration before the shell removes its bundle.
    subprocess.run(["/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", "-u", str(pathlib.Path(sys.argv[1]).parents[2])], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
PY
