import Foundation

/// Folder trust (FEATURES.md → F2). Claude Code asks whether you trust a folder the first time it
/// starts in one, and keeps the answer in its global config as
/// `projects["<folder>"].hasTrustDialogAccepted`. It takes the answer of any folder above the one
/// it starts in, up to that folder's git repository root: read from 2.1.296's code and checked in
/// a pty with a scratch config (2026-10-11). So one entry for the scratch folders' root covers
/// every scratch folder, and a repository cloned into one still asks. Claude Code has no command
/// that sets it, so Calm edits the file the way Claude Code does (`ClaudeCodeConfig`).
public extension ClaudeCodeAdapter {
    func trust(_ folder: URL, home: URL, inherited: [String: String]) -> FolderTrust? {
        ClaudeCodeConfig.trust(folder, in: Self.configFile(home: home, inherited: inherited))
    }

    /// `~/.claude.json`, or `.claude.json` in `CLAUDE_CONFIG_DIR` when that moves it.
    static func configFile(home: URL, inherited: [String: String]) -> URL {
        let folder = inherited["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) }
        return (folder ?? home).appending(path: ".claude.json")
    }
}

/// Claude Code's global config, edited as Claude Code edits it, since every running Claude rewrites
/// the whole file now and then: under its lock, re-read once the lock is held, and replaced in one
/// rename with its permissions kept. The lock is proper-lockfile's, the directory `<file>.lock`;
/// Claude Code holds it for milliseconds and takes one older than ten seconds as stale. Calm waits
/// a moment for a held lock and never breaks one: a stale lock is Claude Code's to clear, and until
/// then Claude simply asks as before.
enum ClaudeCodeConfig {
    /// The entry Claude Code writes for a folder when you trust it and it had none (2.1.296).
    static var trustedEntry: [String: Any] {
        [
            "allowedTools": [String](),
            "mcpContextUris": [String](),
            "mcpServers": [String: Any](),
            "enabledMcpjsonServers": [String](),
            "disabledMcpjsonServers": [String](),
            "hasTrustDialogAccepted": true,
            "hasClaudeMdExternalIncludesApproved": false,
            "hasClaudeMdExternalIncludesWarningShown": false,
        ]
    }

    static func trust(_ folder: URL, in file: URL, lockAttempts: Int = 10) -> FolderTrust {
        // Claude Code keys folders by the path the kernel reports for its working folder.
        let key = TranscriptDiscovery.resolved(folder.path)
        // Most calls end here, without the lock: the folder was trusted at an earlier launch.
        switch config(in: file, trusting: key) {
        case let .done(result): return result
        case .needsEntry: break
        }
        guard let lock = lock(file, attempts: lockAttempts) else { return .unchanged("Claude Code is writing \(file.path)") }
        defer { rmdir(lock) }
        switch config(in: file, trusting: key) {
        case let .done(result):
            return result
        case var .needsEntry(config):
            var projects = config["projects"] as? [String: Any] ?? [:]
            var entry = projects[key] as? [String: Any] ?? trustedEntry
            entry["hasTrustDialogAccepted"] = true
            projects[key] = entry
            config["projects"] = projects
            do {
                try replace(file, with: config)
            } catch {
                return .unchanged(error.localizedDescription)
            }
            return .added
        }
    }

    private enum Reading {
        case done(FolderTrust)
        case needsEntry([String: Any])
    }

    private static func config(in file: URL, trusting key: String) -> Reading {
        switch SendKeysFile.read(file) {
        case .missing:
            // Claude Code makes the file when it first runs; until then there's nothing to add to.
            return .done(.unchanged("no \(file.path)"))
        case .unreadable:
            return .done(.unchanged("\(file.path) doesn't read as JSON"))
        case let .object(config):
            guard let projects = config["projects"] else { return .needsEntry(config) }
            guard let projects = projects as? [String: Any] else { return .done(.unchanged("unexpected projects in \(file.path)")) }
            let entry = projects[key] as? [String: Any]
            return entry?["hasTrustDialogAccepted"] as? Bool == true ? .done(.alreadyTrusted) : .needsEntry(config)
        }
    }

    /// Takes the lock, or gives up after `attempts` tries 20 ms apart.
    private static func lock(_ file: URL, attempts: Int) -> String? {
        let path = file.path + ".lock"
        for attempt in 1 ... max(attempts, 1) {
            if mkdir(path, 0o755) == 0 {
                return path
            }
            guard errno == EEXIST, attempt < attempts else { return nil }
            usleep(20000)
        }
        return nil
    }

    /// Foundation's JSON keeps every value as it was (a real config's 1,063 decimals came back the
    /// same, 2026-10-11); only the layout and key order change, and Claude Code rewrites both its own
    /// way at its next save. A linked config (dotfiles) stays a link: the file it points to is replaced.
    private static func replace(_ file: URL, with config: [String: Any]) throws {
        let target = TranscriptDiscovery.resolved(file.path)
        let mode = (try? FileManager.default.attributesOfItem(atPath: target))?[.posixPermissions] as? NSNumber
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let temporary = target + ".calm-\(UUID().uuidString)"
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: mode ?? NSNumber(value: 0o600)]
        guard FileManager.default.createFile(atPath: temporary, contents: data, attributes: attributes) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temporary])
        }
        guard rename(temporary, target) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            try? FileManager.default.removeItem(atPath: temporary)
            throw error
        }
    }
}
