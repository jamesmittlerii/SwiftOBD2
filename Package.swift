// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SwiftOBD2",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "SwiftOBD2",
            targets: ["SwiftOBD2"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftOBD2",
            resources: [
                .process("Resources")        // ✅ This is required
            ]
        ),
        .testTarget(
            name: "SwiftOBD2Tests",
            dependencies: ["SwiftOBD2"]
        ),
    ]
)
