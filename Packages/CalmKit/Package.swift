// swift-tools-version: 6.2
// UI-free modules of Calm Terminal. Nothing here may import AppKit, SwiftUI or GhosttyKit,
// so everything is unit-testable with `swift test`.

import PackageDescription

let package = Package(
    name: "CalmKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CalmModel", targets: ["CalmModel"]),
        .library(name: "CalmControl", targets: ["CalmControl"]),
    ],
    targets: [
        .target(name: "CalmModel"),
        .target(name: "CalmControl"),
        .testTarget(name: "CalmModelTests", dependencies: ["CalmModel"]),
        .testTarget(name: "CalmControlTests", dependencies: ["CalmControl"]),
    ],
)
