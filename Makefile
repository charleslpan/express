.PHONY: help generate format lint test ci-swift ci-server ci-ios testflight

help:
	@echo "make generate  Generate Express.xcodeproj from project.yml (XcodeGen)"
	@echo "make format    Apply SwiftFormat and SwiftLint autocorrections"
	@echo "make lint      Check formatting and lint without changing files"
	@echo "make test      Run TransitKit's tests with SwiftPM (works on Linux)"
	@echo "make ci-*      What each CI job runs (ci-swift, ci-server, ci-ios); make testflight uploads a build"

generate:
	xcodegen generate

format:
	swiftformat .
	swiftlint --fix --quiet

lint:
	swiftformat --lint .
	swiftlint --strict --quiet

test:
	swift test --package-path Packages/TransitKit

# CI entry points: .github/workflows/ only call these. Grow them here or in scripts/ci/.
ci-swift:
	scripts/ci/lint.sh
	swift test --package-path Packages/TransitKit

ci-server:
	@echo "ci-server: placeholder until B1 adds the server checks"

ci-ios:
	scripts/ci/ios.sh

testflight:
	@echo "testflight: placeholder until F4 adds the TestFlight upload"
