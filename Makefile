.PHONY: help generate format lint test

help:
	@echo "make generate  Generate Express.xcodeproj from project.yml (XcodeGen)"
	@echo "make format    Apply SwiftFormat and SwiftLint autocorrections"
	@echo "make lint      Check formatting and lint without changing files"
	@echo "make test      Run TransitKit's tests with SwiftPM (works on Linux)"

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
