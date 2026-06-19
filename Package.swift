// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AlphaEqt",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "AlphaEqt",
            targets: ["AlphaEqt"]),
    ],
    targets: [
        .target(
            name: "AlphaEqt",
            resources: [
                .process("Fonts"),
            ]
        ),
        .testTarget(
            name: "AlphaEqtTests",
            dependencies: ["AlphaEqt"]
        ),
    ]
)
