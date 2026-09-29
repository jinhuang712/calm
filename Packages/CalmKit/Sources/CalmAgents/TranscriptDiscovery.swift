import Foundation

/// What Calm can see of an agent's process (plain syscalls, nothing spawned).
struct ProcessFacts: Equatable {
    /// The folder the agent was started in; an agent doesn't change its own.
    var directory: String?
    var started: Date?
    /// The files open in the agent and its child processes (an npm launcher runs the agent as
    /// a child).
    var openFiles: [String] = []
    var arguments: [String] = []

    static func of(_ processID: Int32) -> ProcessFacts {
        let family = [processID] + ProcessInspector.descendants(of: processID)
        return ProcessFacts(
            directory: family.lazy.compactMap { ProcessInspector.workingDirectory(of: $0) }.first,
            started: ProcessInspector.startDate(of: processID),
            openFiles: family.flatMap { ProcessInspector.openFiles(of: $0) },
            arguments: ProcessInspector.snapshot(of: processID)?.arguments ?? [],
        )
    }
}

/// What a transcript's first record says about its session.
struct SessionHead {
    var id: String
    var directory: String?
    /// Started from a terminal, by the user. Not a subagent's thread or another app's session
    /// (Codex keeps those in the same folder), which would only make a folder look ambiguous.
    var isTerminalSession = true
}

/// Finding the transcript of a running agent without its help. Two ways, most exact first:
///
/// 1. The agent keeps the file open.
/// 2. Exactly one transcript in the agent's folder was written since it started. Two agents in
///    one folder make that ambiguous, and the answer is "unknown": a card that shows another
///    conversation's recap is worse than one that shows none.
enum TranscriptDiscovery {
    /// Files under `folder` with the given extension, modified at or after `date`; `descending`
    /// looks in the folders below it too.
    static func files(under folder: URL, extension pathExtension: String, since date: Date?, descending: Bool = true) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let options: FileManager.DirectoryEnumerationOptions = descending
            ? [.skipsHiddenFiles]
            : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys, options: options,
        ) else { return [] }
        var found: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == pathExtension {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            // A little slack: file times and process start times are read separately.
            if let date, let modified = values?.contentModificationDate, modified < date.addingTimeInterval(-2) {
                continue
            }
            found.append(url)
        }
        return found
    }

    /// The files one level down: `root/<folder>/<file>`. pi keeps a folder per project there.
    static func files(inFoldersOf root: URL, extension pathExtension: String, since date: Date?) -> [URL] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles],
        )) ?? []
        return folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .flatMap { files(under: $0, extension: pathExtension, since: date, descending: false) }
    }

    /// `roots` are the agent's transcript folders; `candidates` the transcripts worth checking
    /// for way 2; `head` reads a transcript's session id and folder.
    static func locate(
        facts: ProcessFacts,
        roots: [URL],
        candidates: () -> [URL],
        head: (URL) -> SessionHead?,
    ) -> (agentSessionID: String, url: URL)? {
        // The kernel reports real paths, so compare against the roots' real paths.
        let realRoots = roots.map { resolved($0.path) + "/" }
        for file in facts.openFiles {
            let url = URL(filePath: file)
            guard url.pathExtension == "jsonl", realRoots.contains(where: { file.hasPrefix($0) }), let session = head(url)
            else { continue }
            return (session.id, url)
        }
        guard let directory = facts.directory.map(resolved), facts.started != nil else { return nil }
        let matches = candidates().compactMap { url -> (String, URL)? in
            guard let session = head(url), session.isTerminalSession, session.directory.map(resolved) == directory else { return nil }
            return (session.id, url)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    /// The real path (`/tmp` → `/private/tmp`), as the kernel reports it, so two spellings of a
    /// folder compare equal. (Foundation's `resolvingSymlinksInPath` strips `/private` again.)
    /// A path that doesn't exist comes back as it was.
    static func resolved(_ path: String) -> String {
        guard let real = realpath(path, nil) else { return path }
        defer { free(real) }
        return String(cString: real)
    }

    /// The first line of a JSONL file as a record (a session's header), reading at most `limit`
    /// bytes: Codex's is tens of kilobytes.
    static func firstRecord(of url: URL, limit: Int = 1024 * 1024) -> [String: Any]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var data = Data()
        while data.count < limit, let block = try? handle.read(upToCount: 64 * 1024), !block.isEmpty {
            data.append(block)
            if data.contains(0x0A) {
                break
            }
        }
        guard let end = data.firstIndex(of: 0x0A) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data[data.startIndex ..< end])) as? [String: Any]
    }
}
