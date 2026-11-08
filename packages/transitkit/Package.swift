// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TransitKit",
    platforms: [
        .iOS("27.0"),
        .macOS("27.0"),
    ],
    products: [
        .library(name: "TransitKit", targets: ["TransitKit"]),
    ],
    dependencies: [
        // Generates `Client` and `Types` from MOTIS's OpenAPI spec (Sources/TransitKit/openapi.yaml) at build time.
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.14.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.13.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.3.0"),
        // Google-encoded polylines at a given precision, without CoreLocation on Linux.
        .package(url: "https://github.com/raphaelmor/Polyline", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "TransitKit",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "Polyline", package: "Polyline"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
        .testTarget(
            name: "TransitKitTests",
            dependencies: [
                "TransitKit",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "Polyline", package: "Polyline"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
