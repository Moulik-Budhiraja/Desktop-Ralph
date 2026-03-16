// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "cursor-build",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/Proletic/OSX-Query.git", exact: "0.1.2"),
    ],
    targets: [
        .target(
            name: "PenguinOSXKit",
            dependencies: [
                .product(name: "OSXQuery", package: "OSX-Query"),
            ]
        ),
        .executableTarget(
            name: "sprite-sheet-tool",
            dependencies: [
                "PenguinOSXKit",
            ]
        ),
        .executableTarget(
            name: "cursor-build",
            dependencies: [
                "PenguinOSXKit",
            ]
        ),
        .testTarget(
            name: "PenguinOSXKitTests",
            dependencies: [
                "PenguinOSXKit",
            ]
        ),
    ]
)
