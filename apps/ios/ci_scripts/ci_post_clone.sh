#!/usr/bin/env bash
# Xcode Cloud's post-clone step (see AGENTS.md, TestFlight). Express.xcodeproj is generated and git-ignored, so
# generate it from apps/ios/project.yml with the XcodeGen that scripts/ci/ios.sh pins, before Xcode Cloud resolves
# packages from the committed Package.resolved and archives. Write the git-ignored Config/Secrets.xcconfig from the
# GOOGLE_MAPS_IOS_API_KEY secret environment variable when the workflow has one.
set -euo pipefail

XCODEGEN_VERSION=2.46.0
XCODEGEN_SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806

cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/../../..}/apps/ios"

if [[ -n ${GOOGLE_MAPS_IOS_API_KEY:-} ]]; then
    printf 'GOOGLE_MAPS_IOS_API_KEY = %s\n' "$GOOGLE_MAPS_IOS_API_KEY" >Config/Secrets.xcconfig
    echo "Wrote Config/Secrets.xcconfig from GOOGLE_MAPS_IOS_API_KEY."
else
    echo "warning: GOOGLE_MAPS_IOS_API_KEY is not set: building without it, so map screens show \"Map unavailable\"."
fi

tools=$(mktemp -d)
trap 'rm -rf "$tools"' EXIT
curl -fsSL --retry 3 -o "$tools/xcodegen.zip" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
echo "$XCODEGEN_SHA256  $tools/xcodegen.zip" | shasum -a 256 -c -
unzip -q "$tools/xcodegen.zip" -d "$tools"
"$tools/xcodegen/bin/xcodegen" generate --spec project.yml
