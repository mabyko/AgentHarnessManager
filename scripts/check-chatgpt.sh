#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/ahm-chatgpt-check.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
swiftc -swift-version 6 AgentHarnessManager/ChatGPTProtocol.swift \
    AgentHarnessManager/ChatGPTLocalSession.swift AgentHarnessManager/ChatGPTConnection.swift \
    scripts/check-chatgpt.swift -o "$check_dir/check"
"$check_dir/check"
