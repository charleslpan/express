#!/usr/bin/env python3
"""Choose the iOS simulator the ios job tests and screenshots on, and print its UDID, runtime, and name.

Usage: pick-simulator.py <min-ios-version> [--download]

Wants the newest standard iPhone Pro (such as "iPhone 18 Pro"), so screenshots show the phone most people hold: wide
devices such as the iPhone Duo lay the status bar and tab bar out down the side. Walks the available iOS runtimes at
or above the deployment target, newest first, and on each takes an existing "iPhone <n> Pro", or else creates the
newest one the runtime supports (its `supportedDeviceTypes`: Xcode knows more device types than each runtime runs,
and simctl refuses the others with "Incompatible device"). With --download, where no runtime has one, it downloads
the selected Xcode's iOS platform with `xcodebuild -downloadPlatform iOS` and looks again. Failing all that it falls
back to the newest iPhone of any kind with a ::warning::, and exits 1 only where there is no iPhone at all.

Logs every runtime and what it chose, and why, to stderr; prints "<udid>\t<runtime>\t<name>" to stdout.
"""

import json
import re
import subprocess
import sys
import time

PRO = re.compile(r"iPhone (\d+) Pro")


def log(*parts):
    print(*parts, file=sys.stderr, flush=True)


def simctl(*args):
    return subprocess.run(["xcrun", "simctl", *args], capture_output=True, text=True)


def simctl_json(*args):
    result = simctl("list", *args, "--json")
    if result.returncode != 0:
        log(f"::error::simctl list {' '.join(args)} failed: {result.stderr.strip()}")
        sys.exit(1)
    return json.loads(result.stdout)


def version_key(version):
    return [int(part) for part in re.findall(r"\d+", version)]


def pro_number(name):
    match = PRO.fullmatch(name)
    return int(match.group(1)) if match else None


def ios_runtimes(min_version, quiet=False):
    """The available iOS runtimes at or above min_version, newest first, with every one logged unless quiet."""
    runtimes = [r for r in simctl_json("runtimes")["runtimes"] if r.get("platform", "iOS") == "iOS"]
    runtimes.sort(key=lambda r: version_key(r["version"]), reverse=True)
    usable = []
    for runtime in runtimes:
        phones = [t["name"] for t in runtime.get("supportedDeviceTypes", []) if t["name"].startswith("iPhone")]
        if not runtime.get("isAvailable", False):
            note = "unavailable: " + runtime.get("availabilityError", "no reason given")
        elif version_key(runtime["version"]) < version_key(min_version):
            note = f"below the iOS {min_version} deployment target"
        else:
            note = "usable"
            usable.append(runtime)
        if not quiet:
            log(f"Runtime iOS {runtime['version']} ({runtime['identifier']}), {note}; iPhones:", ", ".join(phones) or "none")
    return usable


def newest(items, name_of):
    pros = [item for item in items if pro_number(name_of(item)) is not None]
    return max(pros, key=lambda item: pro_number(name_of(item))) if pros else None


def find_pro(min_version):
    """(udid, runtime id, name) of a standard iPhone Pro on the newest runtime that has or supports one, or None."""
    devices = simctl_json("devices", "available")["devices"]
    for runtime in ios_runtimes(min_version):
        rid = runtime["identifier"]
        existing = newest(devices.get(rid, []), lambda d: d["name"])
        if existing:
            log(f"Chose {existing['name']} on iOS {runtime['version']}: an existing standard iPhone Pro")
            return existing["udid"], rid, existing["name"]
        device_type = newest(runtime.get("supportedDeviceTypes", []), lambda t: t["name"])
        if not device_type:
            log(f"iOS {runtime['version']} supports no standard iPhone Pro; trying an older runtime")
            continue
        created = simctl("create", device_type["name"], device_type["identifier"], rid)
        if created.returncode == 0:
            log(f"Chose {device_type['name']} on iOS {runtime['version']}: created, as the runtime had none")
            return created.stdout.strip(), rid, device_type["name"]
        log(
            f"::warning::simctl create {device_type['name']} on iOS {runtime['version']} failed "
            f"(exit {created.returncode}): {(created.stderr or created.stdout).strip()}"
        )
    return None


def any_iphone(min_version):
    devices = simctl_json("devices", "available")["devices"]
    for runtime in ios_runtimes(min_version, quiet=True):
        phones = [d for d in devices.get(runtime["identifier"], []) if d["name"].startswith("iPhone")]
        if phones:
            return phones[-1]["udid"], runtime["identifier"], phones[-1]["name"]
    return None


def main():
    min_version = sys.argv[1]
    download = "--download" in sys.argv[2:]
    chosen = find_pro(min_version)
    if not chosen and download:
        log("No runtime has a standard iPhone Pro; downloading the iOS platform for this Xcode")
        start = time.monotonic()
        result = subprocess.run(["xcodebuild", "-downloadPlatform", "iOS"], stdout=sys.stderr, stderr=sys.stderr)
        log(f"xcodebuild -downloadPlatform iOS exited {result.returncode} after {time.monotonic() - start:.0f}s")
        if result.returncode == 0:
            chosen = find_pro(min_version)
    if not chosen:
        chosen = any_iphone(min_version)
        if not chosen:
            log(f"::error::No available iPhone simulator on iOS {min_version} or later")
            sys.exit(1)
        log(
            f"::warning::No standard iPhone Pro simulator could be found or created; using {chosen[2]}. "
            "Screenshots will not show the usual iPhone layout (see the runtimes above)."
        )
    print(*chosen, sep="\t")


if __name__ == "__main__":
    main()
