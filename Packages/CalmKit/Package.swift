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
        // The system SQLite behind a small wrapper (FTS5 with the trigram tokenizer for search),
        // shared by the search index and the readers of an agent's own database: no dependency
        // to add. Package-internal.
        .target(name: "CalmSQLite"),
        // Marks: an agent's own animation frames, where it has them (AgentMarkArt.Frames).
        .target(name: "CalmAgents", dependencies: ["CalmModel", "CalmSQLite"], resources: [.copy("Marks")]),
        .target(name: "CalmSearch", dependencies: ["CalmAgents", "CalmModel", "CalmSQLite"]),
        .testTarget(name: "CalmModelTests", dependencies: ["CalmModel"], resources: [.copy("Fixtures")]),
        .testTarget(name: "CalmControlTests", dependencies: ["CalmControl"], resources: [.copy("Fixtures")]),
        .testTarget(name: "CalmAgentsTests", dependencies: ["CalmAgents", "CalmSQLite"], resources: [.copy("Fixtures")]),
        .testTarget(name: "CalmSearchTests", dependencies: ["CalmSearch", "CalmSQLite"]),
    ],
)
