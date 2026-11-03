// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GlassUI",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(name: "GlassUI", targets: ["GlassUI"]),
    ],
    targets: [
        .target(name: "GlassUI"),
        .testTarget(name: "GlassUITests", dependencies: ["GlassUI"]),
    ]
)
