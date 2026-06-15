// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexContextMonitor",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CodexContextCore",
            targets: ["CodexContextCore"]
        ),
        .executable(
            name: "CodexContextMonitor",
            targets: ["CodexContextMonitor"]
        )
    ],
    targets: [
        .target(
            name: "CodexContextCore"
        ),
        .executableTarget(
            name: "CodexContextMonitor",
            dependencies: ["CodexContextCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CodexContextCoreTests",
            dependencies: ["CodexContextCore", "CodexContextMonitor"]
        )
    ]
)
