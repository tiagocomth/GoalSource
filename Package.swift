// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "GoalSource",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "GoalSource",
            targets: ["GoalSource"]
        )
    ],
    targets: [
        .target(
            name: "GoalSource",
            path: "Sources/GoalSource",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "GoalSourceTests",
            dependencies: ["GoalSource"],
            path: "Tests/GoalSourceTests",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
