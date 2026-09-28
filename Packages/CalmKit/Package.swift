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
        .library(name: "CalmAgents", targets: ["CalmAgents"]),
        .library(name: "CalmSearch", targets: ["CalmSearch"]),
    ],
    targets: [
        .target(name: "CalmModel"),
        .target(name: "CalmControl"),
        // Marks: an agent's own animation frames, where it has them (AgentMarkArt.Frames).
        .target(name: "CalmAgents", dependencies: ["CalmModel"], resources: [.copy("Marks")]),
        // Uses the system SQLite (FTS5 with the trigram tokenizer): no dependency to add.
        .target(name: "CalmSearch", dependencies: ["CalmAgents", "CalmModel"]),
        .testTarget(name: "CalmModelTests", dependencies: ["CalmModel"], resources: [.copy("Fixtures")]),
        .testTarget(name: "CalmControlTests", dependencies: ["CalmControl"]),
        .testTarget(name: "CalmAgentsTests", dependencies: ["CalmAgents"], resources: [.copy("Fixtures")]),
        .testTarget(name: "CalmSearchTests", dependencies: ["CalmSearch"]),
    ],
)
