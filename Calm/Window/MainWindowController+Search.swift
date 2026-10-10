import AppKit
import CalmAgents
import CalmModel
import SwiftUI

/// ⌘K: search every session (FEATURES.md → F7, UIUX.md → Search).
extension MainWindowController {
    /// ⌘K: search every session (FEATURES.md → F7).
    func toggleSearch(query: String = "") {
        if searchHost != nil {
            hideSearch()
            return
        }
        let project = manager.workspace.selectedLayout
            .flatMap { manager.workspace.session($0.focusedSessionID) }
            .flatMap { manager.workspace.project($0.projectID)?.path }
        let model = SearchModel(query: query, grouping: SearchGrouping(workspace: manager.workspace), currentProject: project)
        searchModel = model
        // A step off the terminal's background, as the link tag is (UIUX.md → Search).
        let background = (focusedPane?.effectiveBackgroundColor ?? TerminalEngine.shared.config?.backgroundColor)?
            .usingColorSpace(.sRGB)
        let surface = background.flatMap { $0.blended(withFraction: sidebarStyle.isDark ? 0.07 : 0.55, of: .white) }
            .map { Color(nsColor: $0) } ?? sidebarStyle.background
        let view = SearchPanelView(
            model: model,
            style: sidebarStyle,
            surface: surface,
            onOpen: { [weak self] item in self?.openSearchResult(item) },
            onDismiss: { [weak self] in self?.hideSearch() },
        )
        let host = NSHostingView(rootView: view)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host, positioned: .above, relativeTo: nil)
        searchHost = host
        Motion.fadeIn(host, duration: 0.12)
        window?.makeFirstResponder(host)
    }

    func hideSearch() {
        guard let host = searchHost else { return }
        searchHost = nil
        searchModel = nil
        Motion.fadeOutAndRemove(host, duration: 0.1)
        refocus()
    }

    /// Goes to the session if it's open; otherwise resumes it in its folder, in a new session, with
    /// ⌘N's options: the agents' history doesn't say how a conversation was started.
    /// A conversation whose transcript the agent deleted can't be resumed: it gets a plain new
    /// session in its folder.
    func openSearchResult(_ item: SearchPanelModel.Item) {
        hideSearch()
        if let id = item.openSession {
            select(id)
            return
        }
        let result = item.result
        let conversation = AgentConversation(
            kind: result.agent,
            agentSessionID: result.agentSessionID,
            transcriptPath: result.transcriptPath,
        )
        let command = result.transcriptDeleted ? nil : Agents.adapter(for: result.agent)?
            .resumeCommand(for: conversation, settings: manager.settings)
        guard command != nil || result.transcriptDeleted else { return }
        var directory = FileManager.default.homeDirectoryForCurrentUser.path
        if let folder = result.directory, FileManager.default.fileExists(atPath: folder) {
            directory = folder
        }
        hideSettings()
        let session = manager.newSession(in: directory)
        showSelectedLayout(animated: true)
        if let command {
            runAgentCommand(command, in: manager.panes[session.id])
        }
    }
}
