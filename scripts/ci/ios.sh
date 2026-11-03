#!/usr/bin/env bash
# The `ios` CI job (macOS runner, IOS_RUNNER in .github/ci-config.env): select Xcode, install the pinned XcodeGen,
# generate apps/ios/Express.xcodeproj, and run the Express scheme's tests on an iOS simulator.
# Writes build/Express.xcresult, which the workflow uploads as an artifact.
# Usage: ios.sh [test|build] (default test). Outside CI it keeps the selected Xcode instead of switching to
# XCODE_VERSION, so `pnpm turbo run test` works on a Mac without sudo.
set -euo pipefail

MODE="${1:-test}"
case $MODE in
    test | build) ;;
    *) echo "usage: $0 [test|build]" >&2 && exit 2 ;;
esac

XCODEGEN_VERSION=2.46.0
XCODEGEN_SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806

cd "$(dirname "$0")/../.."
# shellcheck source=/dev/null
source .github/ci-config.env
mkdir -p build/tools

echo "::group::Xcode $XCODE_VERSION"
if [[ -n ${CI:-} ]]; then
    # Xcode_<XCODE_VERSION>.app if the image has it, else the newest Xcode_<XCODE_VERSION>* (such as a release candidate).
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
zip=build/tools/xcodegen.zip
curl -fsSL --retry 3 -o "$zip" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
echo "$XCODEGEN_SHA256  $zip" | shasum -a 256 -c -
rm -rf build/tools/xcodegen && unzip -q -o "$zip" -d build/tools
build/tools/xcodegen/bin/xcodegen generate --spec apps/ios/project.yml
echo "::endgroup::"

echo "::group::Simulator"
# The newest available iPhone on the newest iOS runtime of the selected Xcode.
udid=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
runtimes = sorted(
    (r for r in devices if ".SimRuntime.iOS-" in r),
    key=lambda r: [int(p) for p in r.rsplit("iOS-", 1)[1].split("-")],
)
for runtime in reversed(runtimes):
    phones = [d for d in devices[runtime] if d["name"].startswith("iPhone")]
    if phones:
        print(runtime, phones[-1]["udid"], phones[-1]["name"], sep="\t", file=sys.stderr)
        print(phones[-1]["udid"])
        break
')
if [[ -z $udid ]]; then
    echo "::error::No available iPhone simulator" && xcrun simctl list runtimes
    exit 1
fi
echo "::endgroup::"

rm -rf build/Express.xcresult
# -quiet keeps the log to warnings, errors, and test failures; the .xcresult artifact has everything.
xcodebuild "$MODE" \
    -quiet \
    -project apps/ios/Express.xcodeproj \
    -scheme Express \
    -destination "id=$udid" \
    -derivedDataPath build/DerivedData \
    -resultBundlePath build/Express.xcresult \
    CODE_SIGNING_ALLOWED=NO
