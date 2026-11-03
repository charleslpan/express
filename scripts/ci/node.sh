#!/usr/bin/env bash
# The pnpm workspace's checks for the `server` CI job (ubuntu-latest): install with the pnpm that package.json's
# packageManager pins (through Corepack), then Turborepo's lint, typecheck, build, and test over every workspace
# except the Swift ones, which the swift and ios jobs cover.
set -euo pipefail

cd "$(dirname "$0")/../.."
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0 TURBO_TELEMETRY_DISABLED=1

# Corepack shims in build/tools/ put the pinned pnpm first on PATH (without sudo), so Turborepo's own
# `pnpm run` calls use it too.
mkdir -p build/tools/corepack
corepack enable --install-directory build/tools/corepack pnpm
export PATH="$PWD/build/tools/corepack:$PATH"

echo "::group::pnpm install (Node $(node -v), pnpm $(pnpm -v))"
pnpm install --frozen-lockfile
echo "::endgroup::"

pnpm turbo run lint typecheck build test \
    --filter='!@express/ios' --filter='!@express/transitkit' --filter='!@express/glassui'
