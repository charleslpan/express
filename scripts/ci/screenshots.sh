#!/usr/bin/env bash
# Exports the screenshot harness's attachments (apps/ios/UITests) from a result bundle as PNGs named after each
# attachment, such as root-nyc-evening-dark.png, and lists them in the GitHub Actions run summary.
# Xcode's own `xcresulttool export attachments` does the exporting; this only renames its output using the
# manifest.json it writes.
# Usage: screenshots.sh <result.xcresult> <output dir>
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <result.xcresult> <output dir>" >&2 && exit 2
fi
result=$1
out=$2

raw=$(mktemp -d)
trap 'rm -rf "$raw"' EXIT
echo "::group::Screenshots"
xcrun xcresulttool export attachments --path "$result" --output-path "$raw"

# manifest.json: [{"testIdentifier": …, "attachments": [{"exportedFileName": …, "suggestedHumanReadableName": …}]}].
# The suggested name is "<attachment name>_<index>_<UUID>.<ext>"; keep "<attachment name>.<ext>".
mkdir -p "$out"
python3 - "$raw" "$out" <<'PY'
import json, pathlib, re, shutil, sys

raw, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
manifest = raw / "manifest.json"
tests = json.loads(manifest.read_text()) if manifest.exists() else []
for test in tests:
    for attachment in test.get("attachments", []):
        exported = attachment["exportedFileName"]
        if not exported.lower().endswith(".png"):
            continue
        suggested = attachment.get("suggestedHumanReadableName") or exported
        name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}(\.\w+)$", r"\1", suggested)
        shutil.copyfile(raw / exported, out / name)
        print(f"{out / name}  ({test.get('testIdentifier', '?')})")
PY
echo "::endgroup::"

count=$(find "$out" -name '*.png' | wc -l | tr -d ' ')
echo "Exported $count screenshots to $out"
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    run_url="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
    {
        echo "### Screenshots"
        echo
        echo "$count PNGs in [\`screenshots/\` of the \`ios-${GITHUB_RUN_ATTEMPT:-1}\` artifact]($run_url#artifacts):"
        echo
        find "$out" -name '*.png' -exec basename {} \; | sort | sed 's/^/- `/; s/$/`/'
        echo
        echo "Fetch them with \`gh run download $GITHUB_RUN_ID -n ios-${GITHUB_RUN_ATTEMPT:-1} -D /tmp/ci-artifacts\`."
    } >>"$GITHUB_STEP_SUMMARY"
fi
