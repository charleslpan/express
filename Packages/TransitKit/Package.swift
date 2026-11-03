// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TransitKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "TransitKit", targets: ["TransitKit"]),
    ],
    targets: [
        .target(name: "TransitKit"),
        .testTarget(name: "TransitKitTests", dependencies: ["TransitKit"]),
    ]
)
