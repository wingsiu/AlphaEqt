// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RenderCompare",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "RenderCompare",
            dependencies: ["AlphaEqt"],
            path: "."
        )
    ]
)
