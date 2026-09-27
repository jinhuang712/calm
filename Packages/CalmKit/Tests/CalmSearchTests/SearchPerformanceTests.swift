@testable import CalmSearch
import Foundation
import Testing

/// M4.7, opt-in (CALM_REAL_HISTORY=1): indexes this machine's real transcripts into a temporary
/// index and prints timings and sizes only, never content.
struct SearchPerformanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CALM_REAL_HISTORY"] != nil))
    func `indexes and searches the real history`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "calm-perf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "index.sqlite")
        let index = try SearchIndex(url: url)

        var start = Date()
        let first = index.update()
        let fullSeconds = Date().timeIntervalSince(start)
        start = Date()
        let again = index.update()
        let idleSeconds = Date().timeIntervalSince(start)
        let counts = index.counts()
        let bytes = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
            .reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        print(String(
            format: "perf: full index %.1f s (%d files, %d messages), idle update %.0f ms (%d changed), index %.1f MB",
            fullSeconds, first.filesSeen, counts.messages, idleSeconds * 1000, again.filesUpdated, Double(bytes) / 1_000_000,
        ))
        for query in ["zmx", "worktree", "sidebar notif", "终端", "审核记录", "配置文件", ""] {
            start = Date()
            let results = index.search(query)
            print(String(
                format: "perf: query %@ → %d sessions in %.1f ms",
                "\"\(query)\"",
                results.count,
                Date().timeIntervalSince(start) * 1000,
            ))
        }
        #expect(counts.sessions > 0)
    }
}
