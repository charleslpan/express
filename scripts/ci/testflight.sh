#!/usr/bin/env bash
# The `testflight` job (.github/workflows/testflight.yml: pushes to main and manual dispatch, on IOS_RUNNER):
# archive the Express app, sign it with Xcode's automatic signing through an App Store Connect API key, and upload
# it to App Store Connect, where it lands in TestFlight.
#
# Env (GitHub Actions secrets): ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (the AuthKey_<id>.p8 contents, base64),
# APPLE_TEAM_ID, and optionally GOOGLE_MAPS_IOS_API_KEY. Without the four ASC/team secrets (forks, or before they
# are added) it skips cleanly. The build number is GITHUB_RUN_NUMBER (or BUILD_NUMBER); the marketing version is
# MARKETING_VERSION in apps/ios/project.yml.
set -euo pipefail

XCODEGEN_VERSION=2.46.0
XCODEGEN_SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806

cd "$(dirname "$0")/../.."
# shellcheck source=/dev/null
source .github/ci-config.env

if [[ ${GITHUB_EVENT_NAME:-} == pull_request* ]]; then
    echo "::notice::TestFlight upload skipped: never runs on pull requests."
    exit 0
fi
missing=()
for name in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 APPLE_TEAM_ID; do
    [[ -n ${!name:-} ]] || missing+=("$name")
done
if ((${#missing[@]})); then
    echo "::notice::TestFlight upload skipped: missing secrets ${missing[*]}. Add them under Settings > Secrets and" \
        "variables > Actions (see AGENTS.md, TestFlight)."
    exit 0
fi
build_number="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-}}"
if [[ ! $build_number =~ ^[0-9]+$ ]]; then
    echo "::error::Set BUILD_NUMBER (CI uses GITHUB_RUN_NUMBER) to a positive integer." && exit 1
fi

# The API key and the Maps key file exist only for this run; remove them however it ends.
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/testflight.XXXXXX")
secrets_xcconfig=apps/ios/Config/Secrets.xcconfig
cleanup() {
    rm -rf "$work"
    rm -f "$secrets_xcconfig"
}
trap cleanup EXIT

key="$work/AuthKey_$ASC_KEY_ID.p8"
(
    umask 077
    if [[ $ASC_KEY_P8 == *"-----BEGIN"* ]]; then
        printf '%s\n' "$ASC_KEY_P8" >"$key" # Pasted as the raw .p8 rather than base64: use it as is.
    else
        printf '%s' "$ASC_KEY_P8" | base64 --decode >"$key"
    fi
)
if ! grep -q -- "-----BEGIN PRIVATE KEY-----" "$key"; then
    echo "::error::ASC_KEY_P8 isn't a base64-encoded .p8 key (run: base64 -i AuthKey_<id>.p8 | pbcopy)." && exit 1
fi
auth=(
    -allowProvisioningUpdates
    -authenticationKeyPath "$key"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

echo "::group::Xcode $XCODE_VERSION"
if [[ -n ${CI:-} ]]; then
    # As in ios.sh: Xcode_<XCODE_VERSION>.app, else the newest Xcode_<XCODE_VERSION>* (such as a release candidate).
    xcode="/Applications/Xcode_$XCODE_VERSION.app"
    if [[ ! -d $xcode ]]; then
        xcode=$(find /Applications -maxdepth 1 -name "Xcode_$XCODE_VERSION*.app" | sort -V | tail -n 1)
    fi
    if [[ -z $xcode || ! -d $xcode ]]; then
        echo "::error::No Xcode $XCODE_VERSION on this runner. Installed:" && ls -d /Applications/Xcode*.app
        exit 1
    fi
    sudo xcode-select -s "$xcode/Contents/Developer"
fi
xcodebuild -version
echo "::endgroup::"

echo "::group::XcodeGen $XCODEGEN_VERSION"
mkdir -p build/tools
zip=build/tools/xcodegen.zip
curl -fsSL --retry 3 -o "$zip" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
echo "$XCODEGEN_SHA256  $zip" | shasum -a 256 -c -
rm -rf build/tools/xcodegen && unzip -q -o "$zip" -d build/tools
build/tools/xcodegen/bin/xcodegen generate --spec apps/ios/project.yml
echo "::endgroup::"

mkdir -p "$(dirname "$secrets_xcconfig")"
if [[ -n ${GOOGLE_MAPS_IOS_API_KEY:-} ]]; then
    printf 'GOOGLE_MAPS_IOS_API_KEY = %s\n' "$GOOGLE_MAPS_IOS_API_KEY" >"$secrets_xcconfig"
else
    echo "::warning::GOOGLE_MAPS_IOS_API_KEY is missing: this build won't show the Google map."
    printf 'GOOGLE_MAPS_IOS_API_KEY =\n' >"$secrets_xcconfig"
fi

version=$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' apps/ios/project.yml | head -n 1)
echo "Express $version ($build_number), team $APPLE_TEAM_ID"

echo "::group::Archive"
rm -rf build/Express.xcarchive build/export
xcodebuild archive \
    -quiet \
    -project apps/ios/Express.xcodeproj \
    -scheme Express \
    -configuration Release \
    -destination generic/platform=iOS \
    -derivedDataPath build/DerivedData \
    -archivePath build/Express.xcarchive \
    "${auth[@]}" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    CURRENT_PROJECT_VERSION="$build_number"
echo "::endgroup::"

# destination: upload makes -exportArchive sign for distribution and send the build to App Store Connect.
cat >"$work/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>teamID</key>
    <string>$APPLE_TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
PLIST

echo "::group::Upload"
xcodebuild -exportArchive \
    -archivePath build/Express.xcarchive \
    -exportOptionsPlist "$work/ExportOptions.plist" \
    -exportPath build/export \
    "${auth[@]}"
echo "::endgroup::"

echo "::notice::Uploaded Express $version ($build_number) to App Store Connect; it shows in TestFlight once processed."
