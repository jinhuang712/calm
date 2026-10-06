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
        let available = SessionActionSet(session)
        Button("Rename…", action: onRename)
        if let kind = available.resumes {
            Button("Resume \(kind.displayName) Conversation") { actions.resume(session.id) }
        }
        // Resume's place while the agent runs: the two never show together.
        if let kind = available.restarts {
            let pending = manager.restarts[session.id] == .afterTurn
            Button(SessionActionSet.restartTitle(kind, state: session.state, pending: pending)) {
                if pending {
                    actions.cancelRestart(session.id)
                } else {
                    actions.restart(session.id)
                }
            }
            .disabled(manager.restarts[session.id] == .restarting)
        }
        if available.forks {
            Button("Fork into New Split") { actions.fork(session.id, .split) }
            Button("Fork into New Tab") { actions.fork(session.id, .tab) }
        }
        if !available.copies.isEmpty {
            Divider()
            ForEach(available.copies, id: \.self) { copy in
                Button(copy.menuTitle) { actions.copy(session.id, copy) }
            }
            if available.opensFolder {
                Button("Open in Finder") { actions.openFolder(session.id) }
            }
        }
        Divider()
        if available.keepsAsProject {
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
