// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DemoApp",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .visionOS(.v1),
    ],
    dependencies: [
        .package(path: "../")
    ],
    targets: [
        .executableTarget(
            name: "DemoApp",
            dependencies: ["AlphaEqt"]
        ),
    ]
)
