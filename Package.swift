// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Oriel",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OrielCore", targets: ["OrielCore"])
    ],
    targets: [
        .target(
            name: "OrielCore",
            path: "Sources/Core"
        ),
        .testTarget(
            name: "OrielCoreTests",
            dependencies: ["OrielCore"],
            path: "Tests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
