import Foundation
import Testing

/// The version is written in two places: `project.yml` (the app's `CFBundleShortVersionString`, which
/// Diagnostics and install.sh read) and `CLI/main.swift` (what `calm --version` prints). They are
/// released together, so they must not drift.
struct VersionTests {
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent() // CalmTests
        .deletingLastPathComponent() // the repository

    private func text(_ path: String) throws -> String {
        try String(contentsOf: Self.repository.appending(path: path), encoding: .utf8)
    }

    /// The first capture group of `pattern` in `source`.
    private func firstMatch(_ pattern: String, in source: String) throws -> String? {
        let regex = try Regex(pattern)
        guard let match = source.firstMatch(of: regex), match.output.count > 1 else { return nil }
        return match.output[1].substring.map(String.init)
    }

    @Test func `the app and the command-line tool name the same version`() throws {
        let app = try firstMatch(#"CFBundleShortVersionString:\s*"([^"]+)""#, in: text("project.yml"))
        let tool = try firstMatch(#"let version = "([^"]+)""#, in: text("CLI/main.swift"))
        #expect(app != nil)
        #expect(tool != nil)
        #expect(app == tool)
    }

    @Test func `the version is a plain major.minor.patch`() throws {
        let found = try firstMatch(#"CFBundleShortVersionString:\s*"([^"]+)""#, in: text("project.yml"))
        let app = try #require(found)
        let parts = app.split(separator: ".")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { Int($0) != nil })
    }

    @Test func `the checked-in Info.plist carries the version project.yml names`() throws {
        // Info.plist is generated from project.yml (xcodegen) and checked in: a bump that skipped
        // regenerating it would ship the old number.
        let app = try firstMatch(#"CFBundleShortVersionString:\s*"([^"]+)""#, in: text("project.yml"))
        let plist = try firstMatch(#"<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>"#, in: text("Calm/Info.plist"))
        #expect(app != nil)
        #expect(plist == app)
    }
}
