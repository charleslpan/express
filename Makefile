.PHONY: help install generate format lint test ci-swift ci-server ci-ios testflight

help:
	@echo "make install   Install the pnpm workspace (pnpm install)"
	@echo "make generate  Generate apps/ios/Express.xcodeproj from apps/ios/project.yml (XcodeGen)"
	@echo "make format    Apply SwiftFormat and SwiftLint autocorrections"
	@echo "make lint      Check formatting and lint without changing files"
	@echo "make test      Run every workspace's tests with Turborepo (Swift and Xcode skip where missing)"
	@echo "make ci-*      What each CI job runs (ci-swift, ci-server, ci-ios); make testflight uploads a build"

install:
	pnpm install

generate:
	cd apps/ios && xcodegen generate

format:
	swiftformat .
	swiftlint --fix --quiet

lint:
	swiftformat --lint .
	swiftlint --strict --quiet

test:
	pnpm turbo run test

# CI entry points: .github/workflows/ only call these. Grow them here or in scripts/ci/.
# The swift job's container has no Node, so it calls SwiftPM directly; the ios job calls its script directly.
ci-swift:
	scripts/ci/lint.sh
	swift test --package-path packages/transitkit

ci-server:
	scripts/ci/node.sh
	scripts/ci/server.sh

ci-ios:
	scripts/ci/ios.sh test

testflight:
	@echo "testflight: placeholder until F4 adds the TestFlight upload"
