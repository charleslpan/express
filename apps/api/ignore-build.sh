#!/usr/bin/env bash
# Vercel's Ignored Build Step (`ignoreCommand` in vercel.json): exit 0 skips the
# build, exit 1 builds. Previews build only when something the API is built from
# changed since the branch's last successful deployment (or since it left main),
# so iOS-only pull requests push no motis image. Production always builds: the
# nightly Deploy Hook rebuilds the same commit to pick up fresh feeds.
# The paths match the `server` filter in .github/ci-filters.yml.
set -uo pipefail

PATHS=(apps/api packages/tsconfig packages/eslint-config package.json pnpm-lock.yaml pnpm-workspace.yaml turbo.json)

build() { echo "ignore-build: building ($1)"; exit 1; }
skip() { echo "ignore-build: skipping ($1)"; exit 0; }

[ "${VERCEL_ENV:-}" = production ] && build "production"
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || build "not a git checkout"

base="${VERCEL_GIT_PREVIOUS_SHA:-}"
reason="since last deployment ${base:0:7}"
if [ -z "$base" ] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  # First deployment of the branch, or the previous one isn't in the shallow
  # clone: compare with where the branch left main.
  git fetch --quiet --depth=100 origin main 2>/dev/null || build "cannot fetch main"
  base="$(git merge-base HEAD FETCH_HEAD 2>/dev/null)" || build "no merge base with main"
  reason="since main ${base:0:7}"
fi

git diff --quiet "$base" HEAD -- "${PATHS[@]}" && skip "no API changes $reason"
build "API changed $reason"
