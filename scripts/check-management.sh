#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build --package-path Packages/SkillCore --product ahm
management_bin=$(swift build --package-path Packages/SkillCore --show-bin-path)
python3 scripts/check-management.py "$management_bin/ahm"
