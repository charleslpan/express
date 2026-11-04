#!/usr/bin/env bash
# The `ios` CI job (macOS runner, IOS_RUNNER in .github/ci-config.env): select Xcode, install the pinned XcodeGen,
# generate apps/ios/Express.xcodeproj, and run the Express scheme's tests on an iOS simulator.
# Writes build/Express.xcresult and, in test mode, the screenshot harness's PNGs in build/screenshots/ (exported from
# the result bundle by scripts/ci/screenshots.sh); the workflow uploads both in the ios-<attempt> artifact.
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

# In CI, write the git-ignored Maps key file from the GOOGLE_MAPS_IOS_API_KEY secret, as testflight.sh does (empty
# without it: the app builds and shows "Map unavailable"). Outside CI, keep the developer's own file.
if [[ -n ${CI:-} ]]; then
    secrets_xcconfig=apps/ios/Config/Secrets.xcconfig
    trap 'rm -f "$secrets_xcconfig"' EXIT
    if [[ -n ${GOOGLE_MAPS_IOS_API_KEY:-} ]]; then
        printf 'GOOGLE_MAPS_IOS_API_KEY = %s\n' "$GOOGLE_MAPS_IOS_API_KEY" >"$secrets_xcconfig"
    else
        echo "::warning::GOOGLE_MAPS_IOS_API_KEY is missing: map screens will show \"Map unavailable\"."
        printf 'GOOGLE_MAPS_IOS_API_KEY =\n' >"$secrets_xcconfig"
    fi
fi

echo "::group::XcodeGen $XCODEGEN_VERSION"
zip=build/tools/xcodegen.zip
curl -fsSL --retry 3 -o "$zip" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
echo "$XCODEGEN_SHA256  $zip" | shasum -a 256 -c -
rm -rf build/tools/xcodegen && unzip -q -o "$zip" -d build/tools
build/tools/xcodegen/bin/xcodegen generate --spec apps/ios/project.yml
echo "::endgroup::"

echo "::group::Simulator"
# The newest standard iPhone Pro (such as "iPhone 17 Pro") on the newest iOS runtime of the selected Xcode, so
# screenshots show the phone most people hold. Wide devices such as the iPhone Duo lay the status bar and tab bar out
# down the side. Falls back to the newest available iPhone of any kind where the runtime has no standard Pro.
udid=$(xcrun simctl list devices available --json | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
runtimes = sorted(
    (r for r in devices if ".SimRuntime.iOS-" in r),
    key=lambda r: [int(p) for p in r.rsplit("iOS-", 1)[1].split("-")],
)
for runtime in reversed(runtimes):
    phones = [d for d in devices[runtime] if d["name"].startswith("iPhone")]
    if not phones:
        continue
    pros = [d for d in phones if re.fullmatch(r"iPhone (\d+) Pro", d["name"])]
    pros.sort(key=lambda d: int(re.fullmatch(r"iPhone (\d+) Pro", d["name"]).group(1)))
    chosen, why = (pros[-1], "newest standard Pro") if pros else (phones[-1], "no standard Pro; newest iPhone")
    print("Simulator:", chosen["name"], f"({why}) on", runtime, chosen["udid"], file=sys.stderr)
    print(chosen["udid"])
    break
')
if [[ -z $udid ]]; then
    echo "::error::No available iPhone simulator" && xcrun simctl list runtimes
    exit 1
fi
if [[ $MODE == test ]]; then
    # Boot it now to give screenshots a fixed status bar (9:41, full signal and battery).
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 ||
        echo "::warning::Couldn't override the simulator's status bar"
fi
echo "::endgroup::"

rm -rf build/Express.xcresult build/screenshots
# -quiet keeps the log to warnings, errors, and test failures; the .xcresult artifact has everything.
# -skipPackagePluginValidation trusts TransitKit's OpenAPI generator build plugin, which CI cannot click through.
# Export screenshots even when a test fails, so a broken screen can still be seen.
status=0
xcodebuild "$MODE" \
    -quiet \
    -project apps/ios/Express.xcodeproj \
    -scheme Express \
    -destination "id=$udid" \
    -derivedDataPath build/DerivedData \
    -resultBundlePath build/Express.xcresult \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO || status=$?

if [[ $MODE == test && -d build/Express.xcresult ]]; then
    if ! scripts/ci/screenshots.sh build/Express.xcresult build/screenshots && [[ $status -eq 0 ]]; then
        status=1
    fi
fi
exit "$status"
