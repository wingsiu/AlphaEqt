// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AlphaMetricsDumper",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "AlphaMetricsDumper",
            dependencies: ["AlphaEqt"],
            path: "."
        )
    ]
)
