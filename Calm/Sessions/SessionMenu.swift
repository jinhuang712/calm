import CalmAgents
import CalmModel
import SwiftUI

/// A session's actions (FEATURES.md → F12), as the card's right-click menu and the title's ⋯
/// button show them: one list, so the two can't drift. The agent-backed ones appear only where
/// its agent has the command, and the copy and Finder ones only where there is something to give.
struct SessionMenu: View {
    let session: Session
    let manager: SessionManager
    let actions: SidebarActions
    let onRename: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button("Rename…", action: onRename)
        if MainWindowController.resumeCommand(for: session) != nil, let kind = session.resumableConversation?.kind {
            Button("Resume \(kind.displayName) Conversation") { actions.resume(session.id) }
        }
        if MainWindowController.forkCommand(for: session) != nil {
            Button("Fork into New Split") { actions.fork(session.id, .split) }
            Button("Fork into New Tab") { actions.fork(session.id, .tab) }
        }
        let copies = SessionCopy.allCases.filter { $0.text(for: session) != nil }
        if !copies.isEmpty {
            Divider()
            ForEach(copies, id: \.self) { copy in
                Button(copy.menuTitle) { actions.copy(session.id, copy) }
            }
            if !session.isScratch {
                Button("Reveal in Finder") { actions.reveal(session.id) }
            }
        }
        Divider()
        if session.isScratch {
            Button("Keep as Project…") { actions.keepScratch(session.id) }
        } else {
            let projects = manager.workspace.orderedProjects.filter { $0.kind == .project && $0.id != session.projectID }
            if !projects.isEmpty {
                Menu("Move to Project") {
                    ForEach(projects) { project in
                        Button(project.name) { actions.move(session.id, project.id) }
                    }
                }
            }
            if session.isPinned, manager.workspace.project(session.projectID)?.kind == .project {
                Button("Let It Follow Its Folder") { actions.followFolder(session.id) }
            }
        }
        Divider()
        Button("Close Session", action: onClose)
    }
}
