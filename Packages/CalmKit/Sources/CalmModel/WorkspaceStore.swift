import Foundation

/// Saves and restores the workspace as a small JSON file.
///
/// Writes are atomic, so a crash mid-save never leaves a half-written file. A file that
/// can't be read (missing, corrupt, from a newer version) yields an empty workspace, and
/// the unreadable file is kept aside instead of being overwritten.
public struct WorkspaceStore: Sendable {
    public let fileURL: URL

    /// Bumped when the saved format changes incompatibly.
    public static let formatVersion = 1

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/Calm/state.json`.
    public static var standard: WorkspaceStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Calm", directoryHint: .isDirectory)
        return WorkspaceStore(fileURL: directory.appending(path: "state.json"))
    }

    private struct Envelope: Codable {
        var version: Int
        var workspace: Workspace
    }

    public func load() -> Workspace {
        guard let data = try? Data(contentsOf: fileURL) else { return Workspace() }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.version <= Self.formatVersion else {
                keepAside()
                return Workspace()
            }
            return envelope.workspace
        } catch {
            keepAside()
            return Workspace()
        }
    }

    /// Writes the workspace unless the file already says exactly that, and returns whether it
    /// wrote. Saves follow every report and transcript change, and about two in five of them
    /// (the installed Calm, eight sessions, 2026-09-30) came out byte for byte the same; reading
    /// the file back is cheaper than an atomic rewrite, and stays right if anything else wrote it.
    @discardableResult
    public func save(_ workspace: Workspace) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Envelope(version: Self.formatVersion, workspace: workspace))
        if let current = try? Data(contentsOf: fileURL), current == data {
            return false
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        return true
    }

    /// Moves an unreadable state file out of the way, so the next save doesn't destroy it.
    private func keepAside() {
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = fileURL.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: aside)
    }
}
