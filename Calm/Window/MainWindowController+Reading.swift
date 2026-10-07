import AppKit
import CalmModel

/// Reading (FEATURES.md → F8–F10): the files column, the viewer, links and Copy Cell's toast.
extension MainWindowController {
    // MARK: Files column

    /// ⌘\: the focused session's project files.
    func toggleFiles() {
        filesColumn.toggle(project: focusedProjectPath, isScratch: focusedSession?.isScratch == true, in: container) {
            updateMinimumSize()
        }
    }

    #if DEBUG
        /// `files_open:<file>` opens a file as a click on its row does; `files_expand:<folder>`
        /// opens or closes a folder of the tree; `files_state` logs what the column holds.
        func filesColumnForTesting(_ action: String) {
            let model = filesColumn.model
            if action == "files_state" {
                let state = "root \(model.root ?? "none"), \(model.nodes.count) top entries, \(model.rows.count) rows, "
                    + "\(model.changes.count) changes, totals \(model.totals.map { "+\($0.added) −\($0.deleted)" } ?? "none")"
                FileHandle.standardError.write(Data("calm-selftest: files column \(state)\n".utf8))
            } else if action.hasPrefix("files_expand:") {
                let folder = String(action.dropFirst(13))
                model.toggle(folder)
                FileHandle.standardError
                    .write(Data("calm-selftest: files column folder \(folder) open \(model.expanded.contains(folder))\n".utf8))
            } else if action.hasPrefix("files_open:") {
                let path = String(action.dropFirst(11))
                model.open(path)
                let viewed = model.viewedFile ?? "none"
                FileHandle.standardError.write(Data("calm-selftest: files column opened \(path), viewing \(viewed)\n".utf8))
            }
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

    /// The folders a pane's links resolve against: the session's, then its project's.
    private func linkFolders(of view: TerminalSurfaceView) -> (directory: String?, project: String?) {
        let session = manager.workspace.session(view.id)
        return (view.workingDirectory ?? session?.workingDirectory, session.flatMap { manager.workspace.project($0.projectID)?.path })
    }

    func surface(_ view: TerminalSurfaceView, resolveLink text: String) -> Link? {
        let folders = linkFolders(of: view)
        return LinkOpener.resolveExactly(text, directory: folders.directory, projectDirectory: folders.project)
    }

    func surface(_ view: TerminalSurfaceView, hoversLink hover: LinkHover?) {
        guard let hover, let cells = view.rect(row: hover.anchor.row, columns: hover.anchor.columns) else {
            linkTag.hide(animated: true)
            return
        }
        if let number = hover.pastedImage {
            showPastedImageTag(number, in: view, cells: cells)
            return
        }
        let folders = linkFolders(of: view)
        let link = LinkOpener.resolve(hover.text, directory: folders.directory, projectDirectory: folders.project)
        let preview = LinkOpener.preview(of: link, text: hover.text)
        var image: String?
        if preview.kind == .image, case let .file(path, _, _) = link {
            image = path
        }
        linkTag.show(
            preview,
            image: image,
            under: view.convert(cells, to: container),
            in: view.convert(view.bounds, to: container),
            background: view.effectiveBackgroundColor,
            style: sidebarStyle,
        )
    }

    func surface(_ view: TerminalSurfaceView, requestsOpenLink text: String) {
        linkTag.hide(animated: false)
        let (directory, project) = linkFolders(of: view)
        guard let link = LinkOpener.resolve(text, directory: directory, projectDirectory: project) else {
            CopyToast.show("No such file", at: NSPoint(x: container.bounds.midX, y: container.bounds.midY), in: container)
            return
        }
        if case let .file(path, line, _) = link, LinkOpener.prefersViewer, showFile(path, line: line) {
            return
        }
        LinkOpener.openOutside(link)
    }

    // MARK: Pasted images

    func pastedImagePattern(for view: TerminalSurfaceView) -> NSRegularExpression? {
        manager.workspace.session(view.id)?.agent.flatMap { PastedImageLookup.pattern(for: $0.kind) }
    }

    func surface(_ view: TerminalSurfaceView, pastedImage number: Int) -> URL? {
        manager.workspace.session(view.id).flatMap { PastedImageLookup.image(number, in: $0) }
    }

    func surface(_ view: TerminalSurfaceView, requestsOpenPastedImage number: Int) {
        linkTag.hide(animated: false)
        guard let image = surface(view, pastedImage: number) else {
            CopyToast.show("Image not found", at: NSPoint(x: container.bounds.midX, y: container.bounds.midY), in: container)
            return
        }
        if LinkOpener.prefersViewer, showFile(image.path) {
            return
        }
        LinkOpener.openOutside(.file(path: image.path, line: nil, column: nil))
    }

    /// The tag for a pasted image: the picture large, named by its tag, with its size.
    private func showPastedImageTag(_ number: Int, in view: TerminalSurfaceView, cells: NSRect) {
        guard let image = surface(view, pastedImage: number) else {
            linkTag.hide(animated: true)
            return
        }
        var preview = LinkOpener.preview(of: .file(path: image.path, line: nil, column: nil), text: image.path)
        preview.title = "Image #\(number)"
        preview.detail = PastedImageLookup.pixelSize(of: image)
        linkTag.show(
            preview,
            image: image.path,
            isLarge: true,
            under: view.convert(cells, to: container),
            in: view.convert(view.bounds, to: container),
            background: view.effectiveBackgroundColor,
            style: sidebarStyle,
        )
    }

    // MARK: Viewer

    /// Shows a file over the terminal area (FEATURES.md → F10); esc returns to the session.
    /// Returns false for files Calm can't show.
    @discardableResult
    func showFile(_ path: String, line: Int? = nil) -> Bool {
        let session = focusedSession
        let title = session?.displayTitle ?? "session"
        let shown = fileViewer.show(
            path, line: line, over: mainArea, session: session?.id, sessionTitle: title, style: sidebarStyle,
        ) { [weak self] in
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

    /// Going to a session leaves the file open over the one you were in, as it leaves Settings;
    /// otherwise the viewer would keep covering the new session under "Back to" the old one's name.
    /// A file open over `session`, the one now on screen, stays.
    func closeViewer(unlessOver session: Session.ID? = nil) {
        guard fileViewer.isShowing, session == nil || fileViewer.session != session else { return }
        fileViewer.close()
    }

    func surfaceDidCopyCell(_ view: TerminalSurfaceView, at point: NSPoint, whole: Bool) {
        CopyToast.show(whole ? "Cell copied" : "Copied", at: view.convert(point, to: container), in: container)
    }
}
