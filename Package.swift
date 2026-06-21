// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BlockInputKit",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .library(
            name: "BlockInputKit",
            targets: ["BlockInputKit"]
        ),
        .executable(
            name: "BlockInputKitDemo",
            targets: ["BlockInputKitDemo"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")
    ],
    targets: [
        .target(
            name: "BlockInputKit",
            exclude: [
                "AppKit/AGENTS.md",
                "AppKit/CLAUDE.md",
                "AppKit/BlockItem/AGENTS.md",
                "AppKit/BlockItem/CLAUDE.md",
                "AppKit/Mutation/AGENTS.md",
                "AppKit/Mutation/CLAUDE.md",
                "AppKit/Reordering/AGENTS.md",
                "AppKit/Reordering/CLAUDE.md",
                "AppKit/Selection/AGENTS.md",
                "AppKit/Selection/CLAUDE.md",
                "AppKit/SyntaxHighlighting/AGENTS.md",
                "AppKit/SyntaxHighlighting/CLAUDE.md"
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "BlockInputKitDemo",
            dependencies: ["BlockInputKit"],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "BlockInputKitTests",
            dependencies: [
                "BlockInputKit",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            exclude: [
                "AGENTS.md",
                "CLAUDE.md",
                "AppKit/BlockItem/AGENTS.md",
                "AppKit/BlockItem/CLAUDE.md",
                "AppKit/Mutation/AGENTS.md",
                "AppKit/Mutation/CLAUDE.md",
                "AppKit/Performance/AGENTS.md",
                "AppKit/Performance/CLAUDE.md",
                "AppKit/Reordering/AGENTS.md",
                "AppKit/Reordering/CLAUDE.md",
                "AppKit/Selection/AGENTS.md",
                "AppKit/Selection/CLAUDE.md",
                "AppKit/SyntaxHighlighting/AGENTS.md",
                "AppKit/SyntaxHighlighting/CLAUDE.md",
                "AppKit/Snapshots/AGENTS.md",
                "AppKit/Snapshots/CLAUDE.md"
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
