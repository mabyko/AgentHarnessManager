#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/skill-app-state.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
swiftc -swift-version 6 -emit-module -emit-library -module-name SkillCore \
    Packages/SkillCore/Sources/SkillCore/*.swift \
    -emit-module-path "$check_dir/SkillCore.swiftmodule" -o "$check_dir/libSkillCore.dylib"
swiftc -swift-version 6 -I "$check_dir" -L "$check_dir" -lSkillCore \
    -Xlinker -rpath -Xlinker "$check_dir" \
    AgentHarnessManager/AppStore.swift scripts/check-app-state.swift -o "$check_dir/check"
"$check_dir/check"
