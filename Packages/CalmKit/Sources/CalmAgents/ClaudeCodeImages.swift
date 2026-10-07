import Foundation

/// Claude Code's pasted images, as seen on 2026-10-06 (version 2.1.291):
///
/// - `<tmp>/claude-<uid>/<cwd as a project folder>/<sessionId>/images/<n>.png` holds the image
///   behind `[Image #n]` from the paste on, rewritten when the prompt is sent. `<tmp>` is
///   `CLAUDE_CODE_TMPDIR`, else `/tmp`.
/// - A /clear starts a new session id but the numbers go on counting, so a tag from before a
///   /clear names an image in the old session's folder, which the lookup doesn't know: it finds
///   nothing there rather than another image.
///
/// The session is the one in `sessions/<pid>.json` for the running process, else the hooks'.
extension ClaudeCodeAdapter: PastedImageResolving {
    public var pastedImagePattern: String {
        #"\[Image #(\d+)\]"#
    }

    public func pastedImage(_ query: PastedImageQuery) -> URL? {
        Self.pastedImage(query, uid: getuid())
    }

    static func pastedImage(_ query: PastedImageQuery, uid: uid_t) -> URL? {
        guard query.number > 0 else { return nil }
        let name = "\(query.number).png"
        let session = runningSession(processID: query.processID, home: query.home)
        var sessionIDs: [String] = []
        for id in [session?.id, query.agentSessionID].compactMap(\.self) where !sessionIDs.contains(id) {
            sessionIDs.append(id)
        }
        for root in tmpRoots(environment: query.environment, uid: uid) {
            for sessionID in sessionIDs {
                if let url = image(name, of: sessionID, cwd: session?.cwd, in: root) {
                    return url
                }
            }
        }
        return nil
    }

    private static func runningSession(processID: Int32, home: URL) -> (id: String, cwd: String?)? {
        guard processID > 0,
              let data = try? Data(contentsOf: home.appending(path: ".claude/sessions/\(processID).json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["sessionId"] as? String
        else { return nil }
        return (id, object["cwd"] as? String)
    }

    /// Where Claude Code keeps its temporary files: under `CLAUDE_CODE_TMPDIR` when the pane's
    /// shell has it, and under `/tmp` in any case, since the shell may have set it later.
    private static func tmpRoots(environment: [String: String], uid: uid_t) -> [URL] {
        var roots: [URL] = []
        if let tmp = environment["CLAUDE_CODE_TMPDIR"], !tmp.isEmpty {
            roots.append(URL(filePath: tmp).appending(path: "claude-\(uid)"))
        }
        roots.append(URL(filePath: "/tmp/claude-\(uid)"))
        return roots
    }

    /// The image under the session's working directory's folder, or any folder: the directory
    /// may have moved since the session started.
    private static func image(_ name: String, of sessionID: String, cwd: String?, in root: URL) -> URL? {
        var folders = cwd.map { [projectFolder(for: $0)] } ?? []
        folders += ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter { !folders.contains($0) }
        for folder in folders {
            let url = root.appending(path: folder).appending(path: sessionID).appending(path: "images").appending(path: name)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
