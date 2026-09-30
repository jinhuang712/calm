import CalmAgents
import CalmModel
import CalmSearch
import SwiftUI

/// The welcome page's search (UIUX.md → Welcome page): recent sessions, or the ones a query finds,
/// as a flat list. Enter goes to a session if it's open in Calm, otherwise resumes it in its
/// project folder. The index refreshes as the page asks, then typing only queries it. ⌘K lays
/// its results out in groups instead (SearchModel).
@MainActor
@Observable
final class SearchPanelModel {
    struct Item: Identifiable {
        let result: SearchResult
        /// The Calm session showing this conversation, if one is open.
        let openSession: Session.ID?
        var id: String {
            result.transcriptPath
        }
    }

    var query = "" {
        didSet {
            if query != oldValue {
                schedule(refresh: false)
            }
        }
    }

    private(set) var items: [Item] = []
    /// Whether the index knows any session at all: nil until it has answered, then false only while
    /// every answer, including the first (an empty query lists the most recent), came back empty.
    /// The welcome page uses it to decide whether to show a list of sessions.
    private(set) var hasHistory: Bool?
    var selection = 0
    private let currentProject: String?
    private var task: Task<Void, Never>?

    init(query: String = "", currentProject: String?) {
        self.query = query
        self.currentProject = currentProject
        schedule(refresh: true)
    }

    /// Searches off the main thread, debounced while typing.
    private func schedule(refresh: Bool) {
        task?.cancel()
        let query = query
        let project = currentProject
        task = Task { [weak self] in
            if !refresh {
                try? await Task.sleep(for: .milliseconds(70))
            }
            guard !Task.isCancelled else { return }
            let results = await Task.detached(priority: .userInitiated) {
                SearchService.search(query, currentProject: project, refreshing: refresh)
            }.value
            guard !Task.isCancelled, let self else { return }
            let sessions = SessionManager.shared.workspace.sessions
            items = results.map { result in
                let open = sessions.first { $0.runs(transcriptPath: result.transcriptPath, agentSessionID: result.agentSessionID) }
                return Item(result: result, openSession: open?.id)
            }
            selection = min(selection, max(items.count - 1, 0))
            if !items.isEmpty {
                hasHistory = true
            } else if hasHistory == nil {
                hasHistory = false
            }
        }
    }

    var selectedItem: Item? {
        items.indices.contains(selection) ? items[selection] : nil
    }
}
