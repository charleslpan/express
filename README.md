# Express

An ad-free, Liquid Glass transit app for New York City, for iPhone.

## Run it

You need macOS with Xcode 27.2, [Homebrew](https://brew.sh), and Node 22 or later.

```sh
brew install node xcodegen
corepack enable
pnpm install
cd apps/ios && xcodegen generate
open Express.xcodeproj
```

The Xcode project is generated from [`apps/ios/project.yml`](apps/ios/project.yml) and isn't checked in, so run
`xcodegen generate` in `apps/ios` again after pulling changes to it. In Xcode, pick the **Express** scheme and an
iPhone simulator running iOS 27, then press ⌘R. To run on a device, set your team under Signing & Capabilities (and
change the placeholder bundle id `com.charleslpan.express` if you need to).

Run every test that applies on your machine with `pnpm turbo run test`.

## TestFlight

Every push to `main` builds the app and uploads it to TestFlight through the **TestFlight** GitHub Actions workflow;
run it by hand from the Actions tab too. It needs the app record in App Store Connect (bundle id
`com.charleslpan.express`) and four repository secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (an App Store
Connect API key with the Admin role, its `.p8` file base64-encoded), and `APPLE_TEAM_ID`. Without them it skips the
upload. `GOOGLE_MAPS_IOS_API_KEY` adds the Google Maps key to the build. See [AGENTS.md](AGENTS.md#testflight).

## Repository

A [Turborepo](https://turborepo.com) monorepo over pnpm workspaces:

- `apps/ios`: the iOS app (XcodeGen project and `App/`).
- `apps/api`: the backend, deployed on Vercel.
- `packages/transitkit`: transit data and routing logic (builds and tests on Linux with `swift test`).
- `packages/glassui`: shared SwiftUI and Liquid Glass components.
- `packages/tsconfig`, `packages/eslint-config`: shared TypeScript and ESLint configs.

See [AGENTS.md](AGENTS.md) for conventions, tooling, and design rules.

## License

[MIT](LICENSE)
