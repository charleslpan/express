# Express

An ad-free, Liquid Glass transit app for New York City, for iPhone.

## Run it

You need macOS with Xcode 27.2 and [Homebrew](https://brew.sh).

```sh
brew install xcodegen
xcodegen generate
open Express.xcodeproj
```

The Xcode project is generated from [`project.yml`](project.yml) and isn't checked in, so run `xcodegen generate`
again after pulling changes to it. In Xcode, pick the **Express** scheme and an iPhone simulator running iOS 27,
then press ⌘R. To run on a device, set your team under Signing & Capabilities (and change the placeholder bundle id
`com.charleslpan.express` if you need to).

## Repository

- `App/`: the iOS app target.
- `Packages/TransitKit`: transit data and routing logic (builds and tests on Linux with `swift test`).
- `Packages/GlassUI`: shared SwiftUI and Liquid Glass components.
- `server/`: the backend.

See [AGENTS.md](AGENTS.md) for conventions, tooling, and design rules.

## License

[MIT](LICENSE)
