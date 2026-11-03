#!/usr/bin/env bash
# Lint for the `swift` CI job (Linux, in the Swift container): SwiftFormat --lint and SwiftLint --strict.
# Downloads pinned release binaries into build/tools/ so CI doesn't drift with Homebrew.
# Bump a version here and its sha256 together; keep them close to what `brew install` gives on a Mac.
set -euo pipefail

SWIFTFORMAT_VERSION=0.64.5
SWIFTFORMAT_SHA256=56c50d955903cfedbe28996a70e7551a873cdb6dfa5e416d9332925c455ab365
SWIFTLINT_VERSION=0.65.1
SWIFTLINT_SHA256=caeed6f4a679c35539ffaf124f6c4ab4a8416917f7d8796279dc52b74026059d

cd "$(dirname "$0")/../.."
tools="build/tools"
mkdir -p "$tools"

if ! command -v curl >/dev/null || ! command -v unzip >/dev/null; then
    apt-get update -qq && apt-get install -y -qq curl unzip >/dev/null
fi

# fetch <url> <sha256> <dir>: download a zip, verify it, and unpack it into <dir>.
fetch() {
    local zip="$3.zip"
    curl -fsSL --retry 3 -o "$zip" "$1"
    echo "$2  $zip" | sha256sum -c --quiet -
    rm -rf "$3" && mkdir -p "$3" && unzip -q -o "$zip" -d "$3"
}

fetch "https://github.com/nicklockwood/SwiftFormat/releases/download/$SWIFTFORMAT_VERSION/swiftformat_linux.zip" \
    "$SWIFTFORMAT_SHA256" "$tools/swiftformat"
fetch "https://github.com/realm/SwiftLint/releases/download/$SWIFTLINT_VERSION/swiftlint_linux_amd64.zip" \
    "$SWIFTLINT_SHA256" "$tools/swiftlint"

echo "::group::SwiftFormat $SWIFTFORMAT_VERSION"
"$tools/swiftformat/swiftformat_linux" --lint .
echo "::endgroup::"

# The dynamic swiftlint uses the container toolchain's SourceKit, which some rules need.
echo "::group::SwiftLint $SWIFTLINT_VERSION"
"$tools/swiftlint/swiftlint" lint --strict --quiet --no-cache
echo "::endgroup::"
