// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PornBlocker",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BlockerCore", targets: ["BlockerCore"]),
        .executable(name: "blockerd", targets: ["blockerd"]),
        .executable(name: "BlockerApp", targets: ["BlockerApp"]),
    ],
    targets: [
        .target(
            name: "BlockerCore",
            path: "Sources/BlockerCore"
        ),
        .executableTarget(
            name: "blockerd",
            dependencies: ["BlockerCore"],
            path: "Sources/blockerd"
        ),
        .executableTarget(
            name: "BlockerApp",
            dependencies: ["BlockerCore"],
            path: "Sources/BlockerApp"
        ),
    ]
)
