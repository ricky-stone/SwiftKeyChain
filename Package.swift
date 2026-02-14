// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SwiftKeyChain",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "SwiftKeyChain",
            targets: ["SwiftKeyChain"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftKeyChain"
        ),
        .testTarget(
            name: "SwiftKeyChainTests",
            dependencies: ["SwiftKeyChain"]
        ),
    ]
)
