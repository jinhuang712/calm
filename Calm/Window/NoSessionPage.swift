import AppKit
import CalmModel
import SwiftUI

/// What the main area shows while sessions are open but none is chosen, as after closing the one on
/// screen (UIUX.md → No session chosen): the sessions that wait for a look, or with none waiting the
/// welcome page's search and lists. It fills the main area only; the sidebar stays beside it. Calm
/// still never picks a session for the user: the page shows what there is, and they choose.
@MainActor
final class NoSessionPage {
    private weak var mainArea: NSView?
    private var host: NSHostingView<NoSessionView>?
    private(set) var model: NoSessionModel?

    init(mainArea: NSView) {
        self.mainArea = mainArea
    }

    var isShowing: Bool {
        host != nil
    }

    func show(manager: SessionManager, style: SidebarStyle, background: NSColor, actions: NoSessionView.Actions) {
        // One model per showing: the search starts fresh, and refreshes the index, each time.
        let model = self.model ?? NoSessionModel()
        self.model = model
        let view = NoSessionView(manager: manager, model: model, style: style, background: Color(nsColor: background), actions: actions)
        if let host {
            host.rootView = view
            return
        }
        guard let mainArea else { return }
        // Chosen before the first frame, so the page doesn't open on the lists and then swap.
        model.update(sessions: manager.workspace.sessions)
        model.welcome.projects = manager.workspace.madeProjects
        let host = NSHostingView(rootView: view)
        host.frame = mainArea.bounds
        host.autoresizingMask = [.width, .height]
        mainArea.addSubview(host, positioned: .above, relativeTo: nil)
        self.host = host
        Motion.fadeIn(host, duration: 0.2)
        // No terminal is on screen to type into: the keys go to the page (its search field, or ↵ on
        // a waiting card).
        host.window?.makeFirstResponder(host)
    }

    func hide() {
        guard let host else { return }
        self.host = nil
        model = nil
        Motion.fadeOutAndRemove(host, duration: 0.14)
    }

    /// The keys come back to the page, as after Settings or the search panel closes over it.
    func focus() {
        guard let host, let model else { return }
        host.window?.makeFirstResponder(host)
        // The hosting view alone doesn't give SwiftUI's focus back to the cards or the field.
        model.focusRequests += 1
        model.welcome.focusRequests += 1
    }

    /// ⌘K with the lists up: their search field takes the focus, as on the welcome page. False with
    /// the waiting cards up, which have no field: ⌘K then opens the search panel.
    func focusSearch() -> Bool {
        guard let host, let model, model.content == .lists, model.welcome.showsSearch else { return false }
        model.welcome.focusRequests += 1
        host.window?.makeFirstResponder(host)
        return true
    }
}

/// What the page shows, and which waiting card the keys are on.
@MainActor
@Observable
final class NoSessionModel {
    private(set) var content = NoSessionContent.lists
    /// The search and lists. Made with the page, so the index is read by the time they show.
    let welcome = WelcomeModel(firstUse: false)
    /// The waiting card ↵ opens.
    var selected: Session.ID?
    /// The user has typed in the search during this showing (NoSessionContent.choose).
    var searched = false
    /// Bumped when the keys come back to the page, so the cards take them.
    var focusRequests = 0

    private var waiting: NoSessionContent.Waiting? {
        if case let .waiting(waiting) = content {
            waiting
        } else {
            nil
        }
    }

    var waitingIDs: [Session.ID] {
        waiting?.sessionIDs ?? []
    }

    func update(sessions: [Session]) {
        let next = NoSessionContent.choose(sessions: sessions, current: content, searched: searched)
        if next != content {
            content = next
        }
        let kept = waiting?.keeping(selected)
        if kept != selected {
            selected = kept
        }
    }

    func step(_ delta: Int) {
        selected = waiting?.step(from: selected, by: delta)
    }
}
