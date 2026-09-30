import CalmAgents
import CalmControl
import CalmModel
import CalmSearch
import Foundation
import OSLog

/// Keeps the search index fresh and answers searches (FEATURES.md → F7). The index refreshes at
/// launch, every few minutes, and whenever ⌘K opens: an update with nothing new costs a few
/// milliseconds (DESIGNS.md → Search). Everything here may run on any thread.
enum SearchService {
    private static let log = Logger(subsystem: "com.jinhuang.calm", category: "search")

    /// Opened lazily and thread-safely on first use; nil if the index can't be opened, in which
    /// case search quietly finds nothing.
    static let index: SearchIndex? = {
        do {
            return try SearchIndex()
        } catch {
            log.error("search index unavailable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }()

    static var home: URL {
        SearchIndex.defaultHome
    }

    private static let refreshQueue = DispatchQueue(label: "calm.search.refresh", qos: .utility)
    private nonisolated(unsafe) static var timer: DispatchSourceTimer? // set once, on the main thread

    /// Starts background refreshing: now, then every three minutes.
    @MainActor
    static func start() {
        guard timer == nil else { return }
        timer = makeRefreshTimer()
    }

    /// Built outside the main actor: the handler runs on the refresh queue, and a closure written
    /// inside a `@MainActor` function would inherit main-actor isolation and trap there.
    private nonisolated static func makeRefreshTimer() -> DispatchSourceTimer {
        let source = DispatchSource.makeTimerSource(queue: refreshQueue)
        source.schedule(deadline: .now(), repeating: .seconds(180), leeway: .seconds(20))
        source.setEventHandler { refresh() }
        source.resume()
        return source
    }

    /// Indexes what's new (blocking; call off the main thread).
    static func refresh() {
        guard let index else { return }
        let start = Date()
        let stats = index.update(home: home)
        if stats.filesUpdated > 0 || stats.filesRemoved > 0 {
            let seconds = Date().timeIntervalSince(start)
            let files = stats.filesUpdated
            log.info("indexed \(stats.messagesAdded) messages from \(files) files in \(seconds, format: .fixed(precision: 2)) s")
        }
    }

    /// The most results one search returns; a list that holds this many may have more.
    static let resultLimit = 30

    static func search(_ query: String, currentProject: String? = nil, refreshing: Bool = true) -> [SearchResult] {
        guard let index else { return [] }
        if refreshing {
            _ = index.update(home: home)
        }
        return index.search(query, limit: resultLimit, currentProject: currentProject)
    }

    /// `calm search` over the socket.
    static func respond(to request: ControlRequest) -> ControlResponse {
        guard index != nil else { return .failure("The search index isn't available.") }
        let results = search(request.query ?? "")
        return .success(results: results.map { result in
            ControlResponse.SearchHit(
                title: result.title, agent: result.agent.displayName, directory: result.directory,
                lastActive: result.lastActive.timeIntervalSince1970, snippet: result.snippet, transcript: result.transcriptPath,
            )
        })
    }
}
