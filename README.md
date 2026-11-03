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
