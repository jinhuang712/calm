@testable import CalmAgents
import Foundation
import Testing

/// Trusting the scratch folders in Claude Code's own config. That Claude Code takes a trusted
/// folder's answer for the folders under it was checked against the real one (see
/// `ClaudeCodeAdapter.trust`); these check the file.
struct ClaudeCodeTrustTests {
    /// Laid out as Claude Code writes it (`JSON.stringify` with two spaces), with the kinds of value
    /// a real one holds: counts, decimals, a timestamp, nested objects, another folder's entry.
    private let config = """
    {
      "numStartups": 412,
      "firstStartTime": "2026-09-20T08:14:03.117Z",
      "tipsHistory": {
        "new-user-warmup": 7
      },
      "oauthAccount": {
        "emailAddress": "me@example.com"
      },
      "projects": {
        "/Users/me/code/app": {
          "allowedTools": [],
          "hasTrustDialogAccepted": true,
          "lastCost": 0.2731625,
          "lastDuration": 1760172843117
        }
      }
    }
    """

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "calm-trust-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A config file and a scratch root beside it, in a new folder.
    private func setUp(_ contents: String?) throws -> (file: URL, scratch: URL) {
        let home = try folder()
        let scratch = home.appending(path: "scratch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let file = home.appending(path: ".claude.json")
        if let contents {
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
        return (file, scratch)
    }

    private func json(_ url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func projects(_ url: URL) throws -> [String: Any] {
        try #require(json(url)["projects"] as? [String: Any])
    }

    // MARK: Where

    @Test func `the config is ~/.claude.json, or in CLAUDE_CONFIG_DIR`() {
        let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)
        #expect(ClaudeCodeAdapter.configFile(home: home, inherited: [:]).path == "/Users/me/.claude.json")
        #expect(ClaudeCodeAdapter.configFile(home: home, inherited: ["CLAUDE_CONFIG_DIR": "/tmp/claude"])
            .path == "/tmp/claude/.claude.json")
        #expect(ClaudeCodeAdapter.configFile(home: home, inherited: ["CLAUDE_CONFIG_DIR": ""]).path == "/Users/me/.claude.json")
    }

    @Test func `only Claude Code is told`() throws {
        let (_, scratch) = try setUp(nil)
        let home = scratch.deletingLastPathComponent()
        for adapter in Agents.adapters where adapter.kind != .claudeCode {
            #expect(adapter.trust(scratch, home: home, inherited: [:]) == nil)
        }
    }

    // MARK: Adding

    @Test func `a folder gets Claude Code's own entry, and everything else stays as it was`() throws {
        let (file, scratch) = try setUp(config)
        let before = try json(file)
        #expect(ClaudeCodeConfig.trust(scratch, in: file) == .added)

        // Keyed by the path the kernel reports (`/var/folders` → `/private/var/folders`).
        let key = TranscriptDiscovery.resolved(scratch.path)
        #expect(key.hasPrefix("/private/"))
        var after = try json(file)
        var projects = try #require(after["projects"] as? [String: Any])
        let entry = try #require(projects.removeValue(forKey: key) as? [String: Any])
        #expect(NSDictionary(dictionary: entry).isEqual(to: ClaudeCodeConfig.trustedEntry))
        after["projects"] = projects
        #expect(NSDictionary(dictionary: after).isEqual(to: before))
        #expect(!FileManager.default.fileExists(atPath: file.path + ".lock"))

        // Told again, it's already there and the file isn't touched.
        let written = try Data(contentsOf: file)
        #expect(ClaudeCodeConfig.trust(scratch, in: file) == .alreadyTrusted)
        #expect(try Data(contentsOf: file) == written)
    }

    @Test func `an entry Claude Code made without trust keeps its fields`() throws {
        let (file, scratch) = try setUp(nil)
        let key = TranscriptDiscovery.resolved(scratch.path)
        let untrusted = #"{"projects": {"\#(key)": {"hasTrustDialogAccepted": false, "lastSessionId": "a1b2"}}}"#
        try untrusted.write(to: file, atomically: true, encoding: .utf8)
        #expect(ClaudeCodeConfig.trust(scratch, in: file) == .added)
        let entry = try #require(projects(file)[key] as? [String: Any])
        #expect(entry["hasTrustDialogAccepted"] as? Bool == true)
        #expect(entry["lastSessionId"] as? String == "a1b2")
        #expect(entry.count == 2)
    }

    @Test func `a config with no projects yet gets them`() throws {
        let (file, scratch) = try setUp(#"{"numStartups": 1}"#)
        #expect(ClaudeCodeConfig.trust(scratch, in: file) == .added)
        #expect(try projects(file).count == 1)
        #expect(try json(file)["numStartups"] as? Int == 1)
    }

    @Test func `the folder already trusted leaves the file as it is`() throws {
        let (file, scratch) = try setUp(nil)
        let key = TranscriptDiscovery.resolved(scratch.path)
        let trusted = "{\n  \"projects\": {\n    \"\(key)\": {\n      \"hasTrustDialogAccepted\": true\n    }\n  }\n}"
        try trusted.write(to: file, atomically: true, encoding: .utf8)
        #expect(ClaudeCodeConfig.trust(scratch, in: file) == .alreadyTrusted)
        #expect(try String(contentsOf: file, encoding: .utf8) == trusted)
    }

    // MARK: Leaving it alone

    @Test func `no config is left missing: Claude Code makes its own`() throws {
        let (file, scratch) = try setUp(nil)
        guard case .unchanged = ClaudeCodeConfig.trust(scratch, in: file) else {
            Issue.record("expected nothing written")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func `a config that doesn't read, or holds something else as projects, is left as it is`() throws {
        for contents in [#"{"numStartups": 3,"#, #"{"projects": []}"#] {
            let (file, scratch) = try setUp(contents)
            guard case .unchanged = ClaudeCodeConfig.trust(scratch, in: file) else {
                Issue.record("expected nothing written for \(contents)")
                continue
            }
            #expect(try String(contentsOf: file, encoding: .utf8) == contents)
            #expect(!FileManager.default.fileExists(atPath: file.path + ".lock"))
        }
    }

    @Test func `a lock Claude Code holds is waited for and never broken`() throws {
        let (file, scratch) = try setUp(config)
        let lock = file.path + ".lock"
        try FileManager.default.createDirectory(atPath: lock, withIntermediateDirectories: false)
        guard case .unchanged = ClaudeCodeConfig.trust(scratch, in: file, lockAttempts: 2) else {
            Issue.record("expected nothing written while the lock is held")
            return
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == config)
        #expect(FileManager.default.fileExists(atPath: lock))

        // Released, the next try goes through.
        try FileManager.default.removeItem(atPath: lock)
        #expect(ClaudeCodeConfig.trust(scratch, in: file) == .added)
    }

    // MARK: The file itself

    @Test func `a linked config stays a link, and the file keeps its permissions`() throws {
        let (real, scratch) = try setUp(config)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: real.path)
        let link = real.deletingLastPathComponent().appending(path: "linked.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        #expect(ClaudeCodeConfig.trust(scratch, in: link) == .added)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == real.path)
        #expect(try projects(real)[TranscriptDiscovery.resolved(scratch.path)] != nil)
        let mode = try FileManager.default.attributesOfItem(atPath: real.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: real.deletingLastPathComponent().path)
        #expect(!leftovers.contains { $0.contains(".calm-") })
    }
}
