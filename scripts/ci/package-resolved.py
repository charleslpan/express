#!/usr/bin/env python3
"""Check the app's committed Package.resolved against what Xcode just resolved.

Usage: package-resolved.py <workspace-state.json> <Package.resolved> [--write]

Xcode Cloud won't resolve Swift packages itself: it builds from
apps/ios/Express.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved. `xcodebuild
-resolvePackageDependencies` resolves the packages but (as of Xcode 27.2) leaves that file unwritten, so this reads
the pins from SwiftPM's workspace-state.json in DerivedData's SourcePackages instead and compares them (identity,
location, revision, version) with the committed file's, ignoring its originHash. On a mismatch it prints the file to
commit and exits 1; --write writes that file instead.
"""

import json
import sys


def pins_from_state(path):
    with open(path) as f:
        state = json.load(f)
    pins = []
    for dependency in state["object"]["dependencies"]:
        ref = dependency["packageRef"]
        if ref.get("kind") != "remoteSourceControl":
            continue  # Local packages (TransitKit, GlassUI) aren't pinned.
        checkout = dependency["state"].get("checkoutState", {})
        pin_state = {"revision": checkout["revision"]}
        if checkout.get("version"):
            pin_state["version"] = checkout["version"]
        elif checkout.get("branch"):
            pin_state["branch"] = checkout["branch"]
        pins.append(
            {
                "identity": ref["identity"],
                "kind": ref["kind"],
                "location": ref["location"],
                "state": pin_state,
            }
        )
    return sorted(pins, key=lambda pin: pin["identity"])


def committed_pins(path):
    try:
        with open(path) as f:
            return json.load(f).get("pins")
    except FileNotFoundError:
        return None


def render(pins):
    # Xcode's own layout: two-space indent and " : " between keys and values.
    return json.dumps({"pins": pins, "version": 3}, indent=2, separators=(",", " : "), sort_keys=True) + "\n"


def main():
    args = [arg for arg in sys.argv[1:] if arg != "--write"]
    if len(args) != 2:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    state_path, resolved_path = args
    expected = pins_from_state(state_path)
    committed = committed_pins(resolved_path)
    if committed is not None and sorted(committed, key=lambda pin: pin["identity"]) == expected:
        print(f"{resolved_path} matches the {len(expected)} resolved packages.")
        return 0
    if "--write" in sys.argv:
        with open(resolved_path, "w") as f:
            f.write(render(expected))
        print(f"Wrote {resolved_path}: commit it.")
        return 0
    print(render(expected), end="")
    return 1


if __name__ == "__main__":
    sys.exit(main())
