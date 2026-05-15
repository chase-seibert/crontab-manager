// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CrontabManager",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CrontabManager", targets: ["CrontabManager"])
    ],
    targets: [
        .executableTarget(
            name: "CrontabManager",
            path: "Sources/CrontabManager",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "CrontabManagerTests",
            dependencies: ["CrontabManager"],
            path: "Tests/CrontabManagerTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
