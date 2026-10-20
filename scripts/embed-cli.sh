#!/bin/sh
set -eu
cli_scratch="$DERIVED_FILE_DIR/AgentHarnessCLI"
set --
for cli_arch in $ARCHS; do
    set -- "$@" --arch "$cli_arch"
done
swift build --package-path "$SRCROOT/Packages/SkillCore" --scratch-path "$cli_scratch" \
    --configuration release --product ahm "$@"
cli_bin=$(swift build --package-path "$SRCROOT/Packages/SkillCore" --scratch-path "$cli_scratch" \
    --configuration release --show-bin-path "$@")
cli_destination="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/ahm"
mkdir -p "$(dirname "$cli_destination")"
ditto "$cli_bin/ahm" "$cli_destination"
chmod 755 "$cli_destination"
if [ "${CODE_SIGNING_ALLOWED:-NO}" != "NO" ]; then
    codesign --force --options runtime --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$cli_destination"
fi
