import AppKit
import CalmModel

/// Reading (FEATURES.md → F8–F10): the files column, the viewer, links and Copy Cell's toast.
extension MainWindowController {
    // MARK: Files column

    /// ⌘\: the focused session's project files.
    func toggleFiles() {
        filesColumn.toggle(project: focusedProjectPath, isScratch: focusedSession?.isScratch == true, in: container)
    }

    #if DEBUG
        func openFromFilesForTesting(_ path: String) {
            filesColumn.model.open(path)
            let viewed = filesColumn.model.viewedFile ?? "none"
            FileHandle.standardError.write(Data("calm-selftest: files column opened \(path), viewing \(viewed)\n".utf8))
        }
    #endif

    var focusedSession: Session? {
        manager.workspace.selectedLayout.flatMap { manager.workspace.session($0.focusedSessionID) }
    }

    var focusedProjectPath: String? {
        guard let session = focusedSession else { return nil }
        return session.scratchFolder ?? manager.workspace.project(session.projectID)?.path
    }

    // MARK: Links

    func surface(_ view: TerminalSurfaceView, requestsOpenLink text: String) {
        let session = manager.workspace.session(view.id)
        let directory = view.workingDirectory ?? session?.workingDirectory
        let project = session.flatMap { manager.workspace.project($0.projectID)?.path }
        guard let link = LinkOpener.resolve(text, directory: directory, projectDirectory: project) else {
            CopyToast.show("No such file", at: NSPoint(x: container.bounds.midX, y: container.bounds.midY), in: container)
            return
        }
        if case let .file(path, line, _) = link, LinkOpener.prefersViewer, showFile(path, line: line) {
            return
        }
        LinkOpener.openOutside(link)
    }

    // MARK: Viewer

    /// Shows a file over the terminal area (FEATURES.md → F10); esc returns to the session.
    /// Returns false for files Calm can't show.
    @discardableResult
    func showFile(_ path: String, line: Int? = nil) -> Bool {
        let title = manager.workspace.selectedLayout.flatMap { manager.workspace.session($0.focusedSessionID)?.displayTitle } ?? "session"
        let frame = NSRect(x: mainArea.frame.minX, y: 0, width: mainArea.frame.width, height: container.bounds.height)
        let shown = fileViewer.show(path, line: line, over: frame, sessionTitle: title, style: sidebarStyle) { [weak self] in
            guard let self else { return }
            filesColumn.model.viewedFile = nil
            if let pane = focusedPane {
                window?.makeFirstResponder(pane)
            }
        }
        if shown {
            filesColumn.model.viewedFile = path
        }
        return shown
    }

    func surfaceDidCopyCell(_ view: TerminalSurfaceView, at point: NSPoint) {
        CopyToast.show("Cell copied", at: view.convert(point, to: container), in: container)
    }
}
