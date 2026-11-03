#!/usr/bin/env bash
# skip-unless.sh <tool> <command...>: run <command> if <tool> is on PATH, else skip with a message and exit 0.
# Lets `pnpm turbo run test` cover Swift and Xcode workspaces on hosts without those toolchains (such as Linux).
set -euo pipefail

tool="$1"
shift
if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Skipping ${npm_package_name:-$(basename "$PWD")} (${npm_lifecycle_event:-task}): $tool not found on this host."
    exit 0
fi
exec "$@"
