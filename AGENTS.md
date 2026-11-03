# AGENTS.md

Express is an ad-free iPhone transit app for New York City, built with SwiftUI and Liquid Glass.
Many agents work on it in parallel; follow this file so your work fits theirs.

## Layout

| Path | What lives there |
| --- | --- |
| `project.yml` | XcodeGen spec for `Express.xcodeproj`. The project is generated and git-ignored: edit `project.yml`, never the `.xcodeproj`. |
| `App/` | The `Express` app target: app entry point, root view, assets. |
| `App/Features/<Feature>/` | One folder per feature (views, view models, feature-local helpers). Features don't reach into each other's folders; share code through the packages. |
| `Packages/TransitKit/` | Transit models, networking, and routing logic. Platform-neutral: **no UIKit, SwiftUI, or CoreLocation**, so it builds and tests on Linux. Import `FoundationNetworking` behind `#if canImport(FoundationNetworking)`. |
| `Packages/GlassUI/` | Shared SwiftUI components and Liquid Glass styling (iOS 27+). Depends on SwiftUI only, **never on TransitKit**. |
| `server/` | The backend the server tasks build. It has its own [`server/AGENTS.md`](server/AGENTS.md); read it before touching anything there. |
| `.github/` | CI. Workflows are frozen (see [CI](#ci)); `ci-filters.yml` and `ci-config.env` are editable. `ci-ok` is the required check on `main`. |
| `scripts/ci/` | Scripts the CI Make targets call. |

The app target depends on both packages.

## Build and test

First step on a Mac, after every pull that changes `project.yml`:

```sh
brew install xcodegen swiftformat swiftlint   # XcodeGen 2.46.0
xcodegen generate                             # or: make generate
open Express.xcodeproj
```

- **Toolchain:** Xcode 27.2, iOS 27.0 deployment target, iPhone only.
- **On Linux** (agent sandboxes) only TransitKit builds: `swift test --package-path Packages/TransitKit` (or `make test`).
  Everything iOS (the app, GlassUI) is built and tested by CI; don't try to run Xcode.
- **Lint before you push:** `make lint` checks SwiftFormat and SwiftLint; `make format` fixes what it can.

### CI

Workflow files are **frozen**: Vespin's GitHub App can't push anything under `.github/workflows/`, so each change
there costs the developer a manual push. Never edit them. Change what CI does through the files they read instead:

- **Job logic:** the Make targets each job runs (`make ci-swift`, `ci-server`, `ci-ios`, `testflight`), with longer
  scripts in `scripts/ci/`.
- **Which jobs run:** path filters in `.github/ci-filters.yml`. Each filter gates the job of the same name.
- **Settings:** `.github/ci-config.env` (Swift container image, iOS runner label).
- **Secrets** the jobs already receive as env: `GOOGLE_MAPS_IOS_API_KEY` (`ios`, `testflight`), and `ASC_KEY_ID`,
  `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID` (`testflight`).
- `ci-ok` passes when every job passed or was skipped by its filter. It is the only required check on `main`.
- The `ios` job uploads `build/screenshots/**` and `build/*.xcresult` as artifacts, so write output there.

What each job runs:

| Job | Runs on | Make target | What it does |
| --- | --- | --- | --- |
| `changes` | `ubuntu-latest` | none | Reads `ci-config.env` and evaluates `ci-filters.yml`. |
| `swift` | `SWIFT_IMAGE` container | `ci-swift` | `scripts/ci/lint.sh` (pinned SwiftFormat `--lint` and SwiftLint `--strict`), then TransitKit's `swift test`. |
| `server` | `ubuntu-latest` | `ci-server` | The server checks (`scripts/ci/server.sh`, owned by the server tasks). |
| `ios` | `IOS_RUNNER` | `ci-ios` | `scripts/ci/ios.sh`: selects `XCODE_VERSION`, installs pinned XcodeGen 2.46.0, generates the project, runs the `Express` scheme's tests on the newest iPhone simulator, writes `build/Express.xcresult`. |
| `ci-ok` | `ubuntu-latest` | none | `re-actors/alls-green` over every job: failed or cancelled fails it, skipped is fine. |

- **Add a check** to the Make target (or its script) of the job it belongs to, and widen that job's filter if it now
  covers new paths. Tool versions are pinned with checksums in the scripts; bump both together.
- **A new job** means a workflow edit: ask the developer, and have it added to `ci-ok`'s `needs` (and to
  `allowed-skips` if it has a path filter), or `ci-ok` won't wait for it.
- **Read a failure** with `gh pr checks <number>`, then `gh run view <run-id> --log-failed`. For `ios`, the full
  log is in the `ios-<attempt>` artifact's `.xcresult` (`gh run download <run-id> --name ios-1 --dir /tmp/ci-artifacts`,
  then open it in Xcode or read it with `xcrun xcresulttool`).
- **Locally**, `make lint` uses your Homebrew SwiftFormat and SwiftLint; keep them near the versions `lint.sh` pins.
  Workflows can't cache SwiftPM yet (they're frozen and none of the packages has dependencies); ask for an
  `actions/cache` step once one does.

If a change truly needs a workflow edit, ask the developer for it rather than pushing.

### CI screenshots

CI uploads simulator screenshots as workflow artifacts. Fetch them with the GitHub CLI:

```sh
gh run list --branch <your-branch> --workflow CI   # find the run id
gh run download <run-id> --dir /tmp/ci-artifacts   # all artifacts
gh run download <run-id> --name <artifact> --dir /tmp/ci-artifacts
```

## Conventions

- **Swift 6** language mode with complete strict concurrency, everywhere. Mark UI state `@MainActor`; make types that cross actors `Sendable`.
- **Observation** (`@Observable`) for model and view-model state, not `ObservableObject`/`@Published`.
- **Swift Testing** (`import Testing`, `@Test`, `#expect`) for every test, not XCTest (UI tests excepted).
- **SwiftData** for persistence.
- **Libraries over hand-rolled code.** Reach for Apple's and Google's SDKs first, then well-maintained open-source
  Swift packages, before writing your own. Name every new dependency, and why, in the pull request that adds it.
  Planned so far: swift-openapi-generator and `Polyline` in TransitKit; Google Maps and Places SDKs in the app.
- **One feature folder per feature** under `App/Features/`.
- **Formatting** is SwiftFormat's (`.swiftformat`); linting is SwiftLint's (`.swiftlint.yml`). Don't hand-format against them.
- Keep pull requests small and focused on one task; don't rebase or restack other agents' branches.

## Design rules

- Use the **native Liquid Glass APIs** (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`, system bars and
  sheets) rather than imitating glass with blurs and materials.
- Support **light and dark** appearance; use semantic system colors or asset colors with both variants.
- Support **Dynamic Type** up to the accessibility sizes: no fixed font sizes, layouts that wrap or scroll.
- Give every interactive or meaningful element a **VoiceOver label** (and a hint or value where it helps).
- Provide a **Reduce Transparency** fallback: when `accessibilityReduceTransparency` is on, swap glass for an opaque
  background with enough contrast.
