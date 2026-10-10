#if DEBUG
    import AppKit
    import CalmModel

    /// Self-test drivers for moving a project among the others (UIUX.md → Layout). A headless run
    /// can't press or drag, so each does what the pointer would, through the sidebar's own code:
    /// - `project_drag:<name>:<points>[:hold]`: that project's header dragged `points` down (up when
    ///   negative) in ten steps, the pointer in the middle of the list, through the sidebar's drag
    ///   (`ProjectDragModel`, with the sections as the window laid them out), then let go, unless
    ///   `hold` keeps it lifted for a snapshot. Logs where it would land and the projects' order.
    /// - `project_order`: the projects, in the sidebar's order.
    extension MainWindowController {
        func performProjectActionForTesting(_ action: String) -> Bool {
            let parts = action.split(separator: ":").map(String.init)
            switch parts.first {
            case "project_drag" where parts.count >= 3:
                projectDragForTesting(name: parts[1], points: Double(parts[2]) ?? 0, hold: parts.count > 3 && parts[3] == "hold")
            case "project_order":
                logProjectOrderForTesting()
            default:
                return false
            }
            return true
        }

        private func projectDragForTesting(name: String, points: Double, hold: Bool) {
            let order = manager.workspace.madeProjects.map(\.id)
            guard let project = manager.workspace.madeProjects.first(where: { $0.name == name }) else {
                FileHandle.standardError.write(Data("calm-selftest: project_drag: no project \(name)\n".utf8))
                return
            }
            let model = sidebarProjectDrag
            let middle = Double(sidebarHost?.bounds.height ?? 600) / 2
            for step in 1 ... 10 {
                model.changed(
                    project.id,
                    order: order,
                    spacing: SidebarView.groupSpacing,
                    moved: points * Double(step) / 10,
                    location: middle,
                )
            }
            let landing = model.drag.map { "lands at \($0.target), drawn \(Int($0.offset)) pt from its place" } ?? "didn't start"
            FileHandle.standardError.write(Data("calm-selftest: project_drag \(name) \(Int(points)): \(landing)\n".utf8))
            if !hold {
                model.end { [manager] id, position in manager.moveProject(id, to: position) }
                logProjectOrderForTesting()
            }
        }

        private func logProjectOrderForTesting() {
            let names = manager.workspace.madeProjects.map(\.name).joined(separator: ", ")
            FileHandle.standardError.write(Data("calm-selftest: project order \(names)\n".utf8))
        }
    }
#endif
