#!/usr/bin/env bash
# Vercel's Ignored Build Step: exit 0 skips the build, exit 1 builds. A preview
# builds only when something the API is built from changed on its branch, that
# is since the branch left main, so iOS-only pull requests push no motis image.
# (Not since VERCEL_GIT_PREVIOUS_SHA: on a branch that merged main, that range
# holds main's own API changes.) Production always builds: the nightly Deploy
# Hook rebuilds the same commit to pick up fresh feeds. When in doubt, build.
# The paths match the `server` filter in .github/ci-filters.yml.
set -uo pipefail

PATHS=(apps/api packages/tsconfig packages/eslint-config package.json pnpm-lock.yaml pnpm-workspace.yaml turbo.json)

build() { echo "ignore-build: building ($1)"; exit 1; }
skip() { echo "ignore-build: skipping ($1)"; exit 0; }

echo "ignore-build: VERCEL_ENV=${VERCEL_ENV:-unset} ref=${VERCEL_GIT_COMMIT_REF:-unset} sha=${VERCEL_GIT_COMMIT_SHA:-unset}"
[ "${VERCEL_ENV:-}" = production ] && build "production"
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || build "not a git checkout"

# Vercel's clone is shallow: fetch main, then deepen both sides until they meet.
git fetch --quiet --depth=100 origin main 2>/dev/null || build "cannot fetch main"
main="$(git rev-parse FETCH_HEAD)"
base=""
for _ in 1 2 3; do
  base="$(git merge-base HEAD "$main" 2>/dev/null)" && break
  git fetch --quiet --deepen=200 origin main ${VERCEL_GIT_COMMIT_REF:+"$VERCEL_GIT_COMMIT_REF"} 2>/dev/null || break
done
[ -n "$base" ] || build "no merge base with main"

git diff --quiet "$base" HEAD -- "${PATHS[@]}" && skip "no API changes since main ${base:0:7}"
build "API changed since main ${base:0:7}"
