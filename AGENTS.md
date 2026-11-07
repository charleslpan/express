# AGENTS.md

Express is an ad-free iPhone transit app for New York City, built with SwiftUI and Liquid Glass.
Many agents work on it in parallel; follow this file so your work fits theirs.

## Layout

A Turborepo monorepo over pnpm workspaces: deployables in `apps/`, shared code in `packages/`.

| Path | What lives there |
| --- | --- |
| `package.json`, `pnpm-workspace.yaml`, `turbo.json`, `pnpm-lock.yaml` | The workspace root: pnpm 10 (pinned in `packageManager`), Turborepo 2 tasks (`build`, `test`, `lint`, `typecheck`). Every workspace has a `package.json` whose scripts Turborepo runs. |
| `apps/ios/` | The iOS app: `project.yml` (XcodeGen spec for `Express.xcodeproj`, which is generated and git-ignored: edit `project.yml`, never the `.xcodeproj`) `App/` (app target: entry point, root view, assets), and `ci_scripts/` (Xcode Cloud's post-clone step; see [TestFlight](#testflight)). |
| `apps/ios/App/Features/<Feature>/` | One folder per feature (views, view models, feature-local helpers). Features don't reach into each other's folders; share code through the packages. |
| `apps/ios/App/Navigation/`, `apps/ios/App/Location/` | The app shell's shared state: `AppRouter` (`@Observable`: the selected tab, each tab's `NavigationPath`, the sheet on top) and `LocationService` (When In Use permission, asked only when needed, and live updates), both injected with `.environment(_:)`. `RootView` is the tab bar over `Features/Go`, `Nearby`, `Saved`, and `Search`. A feature navigates by calling a router method, which it adds in an extension in its own folder (such as `showJourneys(to:)`), never by wiring navigation into views. |
| `apps/ios/App/Map/` | `MapView`, the one Google map every map screen uses (`GMSMapView` wrapped for SwiftUI), its JSON map styles, and the SDK key setup. |
| `apps/ios/Config/` | `Express.xcconfig` and the Info.plist keys it feeds. `Secrets.xcconfig` (git-ignored; copy `Secrets.example.xcconfig`) holds `GOOGLE_MAPS_IOS_API_KEY`. |
| `apps/ios/UITests/`, `apps/ios/App/Harness/` | The screenshot harness: the `ExpressUITests` target and the app's launch-argument and fixture plumbing (see [Screenshot harness](#screenshot-harness)). |
| `apps/api/` | The backend: the Vercel project `express-server` (`vercel.json` and its services, such as `motis/`). It has its own [`apps/api/AGENTS.md`](apps/api/AGENTS.md); read it before touching anything there. |
| `packages/transitkit/` | TransitKit: transit models, networking, and routing logic. Platform-neutral: **no UIKit, SwiftUI, or CoreLocation**, so it builds and tests on Linux. Import `FoundationNetworking` behind `#if canImport(FoundationNetworking)`. |
| `packages/glassui/` | GlassUI: shared SwiftUI components and Liquid Glass styling (iOS 27+). Depends on SwiftUI only, **never on TransitKit**. |
| `packages/tsconfig/` | Shared strict TypeScript base config: extend `@express/tsconfig/base.json`. |
| `packages/eslint-config/` | Shared flat ESLint config: `export { default } from "@express/eslint-config"` in a workspace's `eslint.config.js`. |
| `.github/` | CI. Workflows are frozen (see [CI](#ci)); `ci-filters.yml` and `ci-config.env` are editable. `ci-ok` is the required check on `main`. |
| `scripts/ci/` | Scripts the CI Make targets (and some workspace scripts) call. `scripts/skip-unless.sh` skips a task cleanly where its toolchain is missing. |

The app target depends on both Swift packages, by relative path from `apps/ios/project.yml`. A new TypeScript
workspace goes in `apps/` or `packages/` with a `package.json` named `@express/<name>`, extends the shared tsconfig
and ESLint config, and keeps `typescript` below 7 (Vercel's Node builder crashes on TS 7).

## Build and test

First step on a Mac, after every pull that changes `apps/ios/project.yml`:

```sh
brew install node xcodegen swiftformat swiftlint   # XcodeGen 2.46.0, Node 22 or 24
corepack enable                                    # the pnpm that package.json pins
pnpm install
cd apps/ios && xcodegen generate                   # or: make generate
open apps/ios/Express.xcodeproj
```

- **Google Maps key:** copy `apps/ios/Config/Secrets.example.xcconfig` to `Secrets.xcconfig` and paste a key. Without
  one the app still builds and map screens show "Map unavailable". CI (`ios.sh`) and Xcode Cloud (`ci_post_clone.sh`)
  write that file from their `GOOGLE_MAPS_IOS_API_KEY` secret. Style the map with the JSON styles in `App/Map/Styles/`, never a map ID:
  map loads without a map ID are free, and a map ID makes them billed.
- **Toolchain:** Xcode 27.2, iOS 27.0 deployment target, iPhone only. Node 22+ with pnpm 10 (via Corepack).
- **Everything at once:** `pnpm turbo run test` (or `make test`) runs every workspace's tests that apply on the host;
  `build`, `lint`, and `typecheck` work the same way. Narrow it with `--filter`, such as
  `pnpm turbo run test --filter=@express/transitkit`. Swift and Xcode tasks print `Skipping …` and pass where
  `swift` or `xcodebuild` is missing. Turborepo caches by each task's inputs; add `--force` to rerun anyway.
- **On Linux** (agent sandboxes) only TransitKit builds: `swift test --package-path packages/transitkit`.
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
  `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID` (`testflight`, dormant: releases go through Xcode Cloud).
- `ci-ok` passes when every job passed or was skipped by its filter. It is the only required check on `main`.
- The `ios` job uploads `build/screenshots/**` and `build/*.xcresult` as artifacts, so write output there.

What each job runs:

| Job | Runs on | Make target | What it does |
| --- | --- | --- | --- |
| `changes` | `ubuntu-latest` | none | Reads `ci-config.env` and evaluates `ci-filters.yml`. |
| `swift` | `SWIFT_IMAGE` container | `ci-swift` | `scripts/ci/lint.sh` (pinned SwiftFormat `--lint` and SwiftLint `--strict`), then TransitKit's `swift test` (directly: the container has no Node). |
| `server` | `ubuntu-latest` | `ci-server` | `scripts/ci/node.sh` (pinned pnpm via Corepack, `pnpm install --frozen-lockfile`, then `pnpm turbo run lint typecheck build test` over every non-Swift workspace), then the API checks (`scripts/ci/server.sh`, owned by the server tasks). |
| `ios` | `IOS_RUNNER` | `ci-ios` | `scripts/ci/ios.sh test`: selects `XCODE_VERSION`, installs pinned XcodeGen 2.46.0, generates `apps/ios/Express.xcodeproj`, fails if resolving packages changes the committed `Package.resolved` (see [TestFlight](#testflight)), runs the `Express` scheme's tests on the newest standard iPhone Pro simulator (see [Screenshot harness](#screenshot-harness)), writes `build/Express.xcresult`. |
| `testflight` (own workflow) | `IOS_RUNNER` | `testflight` | Dormant: `scripts/ci/testflight.sh` skips with a notice without the App Store Connect secrets, which aren't set; Xcode Cloud ships TestFlight builds instead (see [TestFlight](#testflight)). Not part of `ci-ok`. |
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

### TestFlight

Xcode Cloud builds every push to `main` and uploads it to TestFlight. Apple signs (automatic signing for
`DEVELOPMENT_TEAM` `FZ47TN3469`, set on the app target in `project.yml`) and uploads, so there is no App Store Connect
API key, certificate, profile, or GitHub secret. GitHub CI builds for the simulator unsigned (`CODE_SIGNING_ALLOWED=NO`).

- **Post-clone:** Xcode Cloud runs `apps/ios/ci_scripts/ci_post_clone.sh` (it must stay next to `project.yml`, where
  the generated `Express.xcodeproj` lives). It writes `apps/ios/Config/Secrets.xcconfig` from the
  `GOOGLE_MAPS_IOS_API_KEY` environment variable (or warns and builds without it), downloads the XcodeGen that
  `scripts/ci/ios.sh` pins, and generates the project.
- **Package.resolved:** Xcode Cloud won't resolve Swift packages itself, so
  `apps/ios/Express.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` is committed (a `.gitignore`
  exception; the rest of the project stays ignored). The `ios` job resolves packages after generating the project and
  fails if that changes the file, printing the file to commit. After changing a package in `project.yml` or a local
  package's `Package.swift`, commit the file Xcode writes (`make generate`, then File → Packages → Resolve Package
  Versions), or the one the failed `ios` job prints.
- **Versions:** Xcode Cloud sets the build number (`CFBundleVersion`) itself; the marketing version is
  `MARKETING_VERSION` in `apps/ios/project.yml`. Bump that for a new version.
- `ITSAppUsesNonExemptEncryption = NO` is set in `project.yml`, so builds skip the export-compliance question.
- **The old GitHub Actions upload** (`.github/workflows/testflight.yml`, `scripts/ci/testflight.sh`) stays dormant:
  without its App Store Connect secrets it prints a notice and passes. Removing it needs a manual workflow push.

One-time setup, by the developer in Xcode (needs the app record for `com.charleslpan.express` in App Store Connect):

1. Generate and open the project (`make generate`, `open apps/ios/Express.xcodeproj`), then Integrate → Create
   Workflow, and grant Xcode Cloud access to `charleslpan/express` when asked.
2. Start condition: **Branch Changes** on `main`.
3. Action: **Archive**, platform iOS, scheme `Express`, deployment preparation **TestFlight (Internal Testing Only)**.
4. Post-action: **TestFlight Internal Testing**, with the internal testing group.
5. Environment: add `GOOGLE_MAPS_IOS_API_KEY` as a **secret** environment variable, and pick Xcode 27.2 or later.

### Screenshot harness

You can't open a simulator, so judge your UI from the screenshots CI takes. The `ios` job runs the
`ExpressUITests` target (`apps/ios/UITests/`), which launches the app once per screen and variant and attaches
a screenshot of each. `scripts/ci/screenshots.sh` then exports those attachments to `build/screenshots/` with
Xcode's `xcrun xcresulttool export attachments`. Every screen is captured in three variants: `light`, `dark`, and
`light-ax5` (the largest accessibility text size). The status bar is fixed at 9:41 with full signal. The simulator
is the newest standard iPhone Pro (such as "iPhone 18 Pro"), never a wide device such as the iPhone Duo, which puts
the status bar and tab bar down the side. `scripts/ci/pick-simulator.py` chooses it: it walks the runner's iOS
runtimes at or above the deployment target, newest first, and takes an existing `iPhone <n> Pro` or creates the
newest one the runtime's `supportedDeviceTypes` lists (Xcode ships device types a runtime can't run, and simctl
refuses those with "Incompatible device"). On `xcode-27` the newest runtime, iOS 27.1, runs only the Duo, so CI uses
an older runtime that runs a Pro. Where no runtime does, it downloads the iOS platform
(`xcodebuild -downloadPlatform iOS`) and looks again, and failing that falls back to the newest iPhone of any kind
with a `::warning::`. The `ios` job's Simulator group logs every runtime, each simctl error, and the device chosen.

The app reads these launch arguments (`apps/ios/App/Harness/`):

| Argument | Effect |
| --- | --- |
| `-screenshot <screen>` | Show only that `ScreenshotScreen` case, with animations off. |
| `-fixtures <set>` | Back the data clients with that `FixtureSet` (such as `nyc-evening`) instead of live data: `AppEnvironment.fixtures` names it, and `AppEnvironment.now` returns its reference date. `TransitClient` takes fixtures through its `transport:` (see `AppEnvironment`'s doc comment). Screenshot launches skip the foreground warm-up request. |
| `-appearance light\|dark` | Force the appearance. |
| `-UIPreferredContentSizeCategoryName <category>` | The system's own text-size override. |

**Add a screen** in the same pull request that builds it:

1. Add a case to `ScreenshotScreen` (`App/Harness/ScreenshotScreen.swift`) that returns the screen's view. Set it up
   from the environment (`\.transitClient`, `AppEnvironment.now`), never from live services or the clock.
2. Add a `FixtureSet` case if you need new data. Your fixture-backed client switches over it to decide what to return.
3. Add a test to `UITests/ScreenshotTests.swift` that calls `capture("<screen>", fixtures: "<set>")`. Name a
   screen and its fixtures in lowercase with hyphens. Each test writes `<screen>-<fixtures>-<variant>.png`.

**Look at the screenshots** once the `ios` job has finished. Its run summary lists the PNGs.

```sh
gh run list --branch <your-branch> --workflow CI                  # find the run id
gh run download <run-id> -n ios-1 -D /tmp/ci-artifacts            # ios-<attempt>; the PNGs are in screenshots/
ls /tmp/ci-artifacts/screenshots                                  # then open each PNG with your Read tool
```

The frozen workflow uploads the PNGs inside the `ios-<attempt>` artifact (next to `Express.xcresult`), not in an
artifact of their own. The PNGs are exported even when a test fails.

## Conventions

- **Swift 6** language mode with complete strict concurrency, everywhere. Mark UI state `@MainActor`; make types that cross actors `Sendable`.
- **Observation** (`@Observable`) for model and view-model state, not `ObservableObject`/`@Published`.
- **Swift Testing** (`import Testing`, `@Test`, `#expect`) for every test, not XCTest (UI tests excepted).
- **SwiftData** for persistence.
- **Libraries over hand-rolled code.** Reach for Apple's and Google's SDKs first, then well-maintained open-source
  Swift packages, before writing your own. Name every new dependency, and why, in the pull request that adds it.
  Planned so far: swift-openapi-generator and `Polyline` in TransitKit; Google Maps and Places SDKs in the app.
- **One feature folder per feature** under `apps/ios/App/Features/`.
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
