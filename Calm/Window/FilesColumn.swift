import AppKit
import CalmModel
import SwiftUI

/// The files column (FEATURES.md → F10): the focused session's project, right of the sidebar.
/// What changed comes first, with the lines each change adds and removes; then the tree, with
/// git-ignored files hidden. ⌘\ toggles it; a click opens the viewer.
@MainActor
@Observable
final class FilesModel {
    var root: String?
    /// Set while `root` is a scratch session's folder.
    var isScratch = false
    var branch: String?
    var nodes: [FileNode] = []
    var changes: [ChangedFile] = []
    /// Folders open in the tree, relative to `root`; all close again for another folder.
    var expanded: Set<String> = []
    var style = SidebarStyle.derived(from: NSColor(white: 0.12, alpha: 1))
    var viewedFile: String?
    var onOpen: (String) -> Void = { _ in }
    private var loading: Task<Void, Never>?

    /// Opens a file of the tree (a path relative to `root`) in the viewer.
    func open(_ path: String) {
        guard let root else { return }
        onOpen((root as NSString).appendingPathComponent(path))
    }

    func isViewed(_ path: String) -> Bool {
        root.map { ($0 as NSString).appendingPathComponent(path) } == viewedFile
    }

    /// Opens or closes a folder of the tree.
    func toggle(_ folder: String) {
        if expanded.remove(folder) == nil {
            expanded.insert(folder)
        }
    }

    /// The tree's rows, with the open folders' children.
    var rows: [FileRow] {
        FileNode.rows(nodes, expanded: expanded)
    }

    /// Every line the changes add and remove, when git could count any.
    var totals: LineCounts? {
        let counted = changes.compactMap(\.lines)
        return counted.isEmpty ? nil : counted.reduce(LineCounts(added: 0, deleted: 0), +)
    }

    /// The column's heading. A scratch session's folder name is Calm's business.
    var title: String {
        guard let root else { return "No project" }
        return isScratch ? "Scratch" : WorkspacePath.displayName(for: root)
    }

    /// Shows `root`'s tree, reading it again if it's a different folder or `force`d.
    func follow(_ root: String?, isScratch: Bool = false, force: Bool = false) {
        guard force || root != self.root else { return }
        if root != self.root {
            nodes = []
            branch = nil
            changes = []
            expanded = []
        }
        self.root = root
        self.isScratch = isScratch
        guard let root else { return }
        loading?.cancel()
        loading = Task { [weak self] in
            let listing = await Task.detached(priority: .utility) { FilesListing.read(root) }.value
            guard !Task.isCancelled, let self, self.root == root else { return }
            nodes = FileNode.tree(paths: listing.paths, changes: listing.changes)
            branch = listing.branch
            changes = ChangedFile.list(changes: listing.changes, lines: listing.lines)
        }
    }
}

/// Reads a folder's files: through git when it's in a repository (ignored files left out,
/// changes marked), else a bounded walk of the folder.
enum FilesListing {
    struct Result {
        var paths: [String] = []
        var changes: [String: GitChange] = [:]
        /// The lines each change adds and removes, against the last commit.
        var lines: [String: LineCounts] = [:]
        var branch: String?
    }

    static func read(_ root: String) -> Result {
        guard let prefix = git(["rev-parse", "--show-prefix"], in: root) else { return walk(root) }
        var result = Result()
        let prefixPath = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        result.paths = (git(["ls-files", "-co", "--exclude-standard", "-z"], in: root) ?? "")
            .split(separator: "\0").map(String.init)
        // Status paths are relative to the repository; the tree is relative to `root`.
        for (path, change) in GitChange.parse(porcelain: git(["status", "--porcelain=v1", "-z", "-uall"], in: root) ?? "")
            where path.hasPrefix(prefixPath) {
            result.changes[String(path.dropFirst(prefixPath.count))] = change
        }
        // Staged and unstaged changes together, as `status` shows them. `--relative` gives paths
        // relative to `root`, like the tree's. A repository without commits has no HEAD: no counts.
        result.lines = LineCounts.parse(numstat: git(["diff", "--numstat", "-z", "--relative", "HEAD"], in: root) ?? "")
        countUntracked(&result, in: root)
        result.branch = git(["branch", "--show-current"], in: root)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    /// `git diff` leaves untracked files out; every line of one is added. Bounded, since this
    /// runs every 5 seconds while the column is shown: files up to 512 KB, 4 MB in all.
    private static func countUntracked(_ result: inout Result, in root: String) {
        var budget = 4 << 20
        let base = URL(filePath: root, directoryHint: .isDirectory)
        for path in result.changes.filter({ $0.value == .untracked }).keys.sorted() {
            let url = base.appending(path: path)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 512 << 10, size <= budget,
                  let data = try? Data(contentsOf: url)
            else { continue }
            budget -= size
            if let lines = LineCounts.lines(in: data) {
                result.lines[path] = LineCounts(added: lines, deleted: 0)
            }
        }
    }

    private static func git(_ arguments: [String], in folder: String) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", folder] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(bytes: data, encoding: .utf8)
    }

    /// Outside a repository: files under the folder, skipping hidden and build folders, bounded.
    /// Breadth first, so a big first folder can't use up the limit before its siblings are seen
    /// (a home folder's `go` or `Library`). Paths are built relative to `root` as the walk goes
    /// down, which also survives symlinked folders (`/tmp` is `/private/tmp`).
    static func walk(_ root: String, limit: Int = 5000) -> Result {
        var result = Result()
        let skipped: Set = ["node_modules", "build", "DerivedData", "Pods", "target", "dist"]
        let base = URL(filePath: root, directoryHint: .isDirectory)
        var folders = [""]
        while !folders.isEmpty, result.paths.count < limit {
            let folder = folders.removeFirst()
            let url = folder.isEmpty ? base : base.appending(path: folder, directoryHint: .isDirectory)
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles],
            )) ?? []
            let sorted = entries.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            for entry in sorted {
                let name = entry.lastPathComponent
                let path = folder.isEmpty ? name : "\(folder)/\(name)"
                if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    if !skipped.contains(name), !name.hasSuffix(".app") {
                        folders.append(path)
                    }
                } else if result.paths.count < limit {
                    result.paths.append(path)
                }
            }
        }
        return result
    }
}

/// Places the column between the sidebar and the terminal area and slides it in and out.
@MainActor
final class FilesColumn {
    /// 272 points at the standard interface size: room for a change's name, folder and lines.
    static var width: CGFloat {
        272.scaled
    }

    let model = FilesModel()
    private let host: NSHostingView<FilesColumnView>
    private var widthConstraint: NSLayoutConstraint?
    private var timer: Timer?

    var isShown: Bool {
        (widthConstraint?.constant ?? 0) > 0
    }

    init(onOpen: @escaping (String) -> Void) {
        let model = model
        model.onOpen = onOpen
        host = NSHostingView(rootView: FilesColumnView(model: model))
    }

    /// Adds the column right after `sidebar`; returns it for the terminal area to follow.
    func install(in container: NSView, after sidebar: NSView) -> NSView {
        host.translatesAutoresizingMaskIntoConstraints = false
        // Clipped here rather than in SwiftUI: `.clipped()` would also cut the background off at the
        // title bar's safe area. Clipping keeps the list inside while the width animates from 0.
        host.clipsToBounds = true
        // The width constraint alone sizes the column; SwiftUI's own size constraints would fight 0.
        host.sizingOptions = []
        container.addSubview(host)
        let width = host.widthAnchor.constraint(equalToConstant: 0)
        widthConstraint = width
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            width,
        ])
        return host
    }

    func toggle(project: String?, isScratch: Bool, in container: NSView) {
        guard let widthConstraint else { return }
        let show = !isShown
        if show {
            model.follow(project, isScratch: isScratch, force: true)
            // Changes appear while the column is open; reading a repository's listing is cheap.
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let model = self?.model else { return }
                    model.follow(model.root, isScratch: model.isScratch, force: true)
                }
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
        Motion.animateLayout(of: container) {
            widthConstraint.constant = show ? Self.width : 0
        }
    }

    /// Follows the interface size; a hidden column stays hidden.
    func updateWidth() {
        guard let widthConstraint, isShown, widthConstraint.constant != Self.width else { return }
        widthConstraint.constant = Self.width
    }
}

/// The column in the sidebar's colors and metrics (UIUX.md → Layout): its header on the search
/// field's line, its first section header level with the sidebar's first group.
struct FilesColumnView: View {
    let model: FilesModel

    var body: some View {
        let style = model.style
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: CalmWindow.titleStripHeight)
            header(style: style)
                .padding(.horizontal, 16.scaled)
                .frame(height: 40.scaled)
                .padding(.bottom, 18.scaled)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !model.changes.isEmpty {
                        sectionHeader("Changes", count: model.changes.count, style: style)
                        ForEach(model.changes) { change in
                            FilesChangeRow(change: change, viewed: model.isViewed(change.path), style: style) {
                                model.open(change.path)
                            }
                        }
                        Rectangle()
                            .fill(style.tertiary.opacity(0.14))
                            .frame(height: 1)
                            .padding(.horizontal, 16.scaled)
                            .padding(.vertical, 12.scaled)
                        sectionHeader("Files", count: nil, style: style)
                    }
                    ForEach(model.rows) { row in
                        FilesTreeRow(row: row, expanded: model.expanded.contains(row.id), viewed: model.isViewed(row.id), style: style) {
                            if row.node.isFolder {
                                withAnimation(Motion.isReduced ? nil : .easeOut(duration: 0.18)) { model.toggle(row.id) }
                            } else {
                                model.open(row.id)
                            }
                        }
                    }
                }
                .padding(.bottom, 16.scaled)
            }
            .scrollIndicators(.never)
        }
        .frame(width: FilesColumn.width)
        .frame(maxHeight: .infinity, alignment: .top)
        // The title strip's room is counted above, as the sidebar does.
        .ignoresSafeArea(.container, edges: .top)
        // One surface with the sidebar, a hairline between them like the sidebar footer's.
        .background(style.background.opacity(style.surfaceOpacity).ignoresSafeArea())
        .overlay(alignment: .leading) { Rectangle().fill(style.tertiary.opacity(0.14)).frame(width: 1).ignoresSafeArea() }
        // Laid out at full width and clipped while the column slides, never squeezed.
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, style.isDark ? .dark : .light)
    }

    /// The project, its branch and every line its changes add and remove. The branch shows whole
    /// or not at all: cut down, it was a stray letter in a pill.
    private func header(style: SidebarStyle) -> some View {
        ViewThatFits(in: .horizontal) {
            headerRow(branch: model.branch, style: style)
            headerRow(branch: nil, style: style)
        }
        .accessibilityElement(children: .combine)
    }

    private func headerRow(branch: String?, style: SidebarStyle) -> some View {
        HStack(spacing: 8.scaled) {
            Text(model.title)
                .calmFont(size: 13.5, weight: .medium)
                .foregroundStyle(style.primary)
                .lineLimit(1)
            if let branch, !branch.isEmpty {
                GitPill(text: branch, kind: "branch", style: style)
            }
            Spacer(minLength: 4.scaled)
            if let totals = model.totals {
                LineCountsLabel(lines: totals, size: 11.5, style: style)
            }
        }
    }

    /// Drawn like the sidebar's project names: small capitals, tracked.
    private func sectionHeader(_ title: String, count: Int?, style: SidebarStyle) -> some View {
        HStack(spacing: 7.scaled) {
            Text(title.uppercased())
                .calmFont(size: 12, weight: .semibold)
                .tracking(0.7)
            if let count {
                Text("\(count)")
                    .calmFont(size: 12)
                    .opacity(0.75)
            }
        }
        .foregroundStyle(style.tertiary)
        .padding(.horizontal, 16.scaled)
        .frame(height: 26.scaled)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// `+64 −31`, in the sage of *done* and the muted red of *failed*; a side with nothing is left out.
private struct LineCountsLabel: View {
    let lines: LineCounts
    let size: CGFloat
    let style: SidebarStyle

    var body: some View {
        HStack(spacing: 4.scaled) {
            if lines.added > 0 {
                Text("+\(lines.added)").foregroundStyle(style.done)
            }
            if lines.deleted > 0 {
                Text("−\(lines.deleted)").foregroundStyle(style.failure)
            }
        }
        .calmFont(size: size, design: .monospaced)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(lines))
    }

    static func spoken(_ lines: LineCounts) -> String {
        "\(lines.added) lines added, \(lines.deleted) removed"
    }
}

/// A row of Changes: the change's letter, the file, its folder and its lines. Files are buttons
/// rather than selected rows, as in the tree.
private struct FilesChangeRow: View {
    let change: ChangedFile
    let viewed: Bool
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8.scaled) {
                Text(change.change.rawValue)
                    .calmFont(size: 10.5, weight: .medium, design: .monospaced)
                    .foregroundStyle(change.change == .deleted ? style.failure : style.secondary)
                    .frame(width: 18.scaled, height: 18.scaled)
                    .background(RoundedRectangle(cornerRadius: 5.scaled, style: .continuous)
                        .fill(style.primary.opacity(viewed ? 0.09 : 0.055)))
                Text(change.name)
                    .calmFont(size: 13.5, weight: viewed ? .medium : nil)
                    .foregroundStyle(style.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                if !change.folderName.isEmpty {
                    // Whole or not at all, after the file's name: cut down it read as stray
                    // letters. The full path is the row's tooltip.
                    ViewThatFits(in: .horizontal) {
                        Text(change.folderName)
                            .calmFont(size: 11.5)
                            .foregroundStyle(style.tertiary)
                            .lineLimit(1)
                            .fixedSize()
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
                Spacer(minLength: 4.scaled)
                if let lines = change.lines {
                    LineCountsLabel(lines: lines, size: 11, style: style)
                }
            }
            .padding(.horizontal, 8.scaled)
            .frame(height: 30.scaled)
            .background(FilesRowBackground(viewed: viewed, hovering: hovering, style: style))
            .contentShape(Rectangle())
            .padding(.horizontal, 8.scaled)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(change.path)
        .accessibilityLabel(label)
    }

    private var label: String {
        let parts = [
            change.name,
            change.folder.isEmpty ? nil : "in \(change.folder)",
            change.change.spoken,
            change.lines.map(LineCountsLabel.spoken),
        ]
        return parts.compactMap(\.self).joined(separator: ", ")
    }
}

/// A row of the tree: a chevron for a folder in a fixed gutter, so names line up at each depth.
private struct FilesTreeRow: View {
    let row: FileRow
    let expanded: Bool
    let viewed: Bool
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let node = row.node
        Button(action: action) {
            HStack(spacing: 6.scaled) {
                Group {
                    if node.isFolder {
                        Image(systemName: "chevron.down")
                            .calmFont(size: 9, weight: .medium)
                            .rotationEffect(.degrees(expanded ? 0 : -90))
                    }
                }
                .frame(width: 16.scaled)
                .foregroundStyle(style.tertiary)
                Text(node.name)
                    .calmFont(size: 13.5, weight: viewed ? .medium : nil)
                    .foregroundStyle(nameColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4.scaled)
                if node.isFolder {
                    if node.change != nil {
                        Circle().fill(style.tertiary).frame(width: 5.scaled, height: 5.scaled)
                    }
                } else if let change = node.change {
                    Text(change.rawValue)
                        .calmFont(size: 11, weight: .medium, design: .monospaced)
                        .foregroundStyle(change == .deleted ? style.failure : style.tertiary)
                }
            }
            // 12 points from the column's edge at the top, 16 more per level (8 of them are the
            // highlight's inset below).
            .padding(.leading, (4 + 16 * CGFloat(row.depth)).scaled)
            .padding(.trailing, 8.scaled)
            .frame(height: 26.scaled)
            .background(FilesRowBackground(viewed: viewed, hovering: hovering, style: style))
            .contentShape(Rectangle())
            .padding(.horizontal, 8.scaled)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(node.isFolder ? (expanded ? "expanded" : "collapsed") : "")
    }

    /// Changed files stand out, dotfiles step back.
    private var nameColor: Color {
        if viewed || (!row.node.isFolder && row.node.change != nil) {
            return style.primary
        }
        return row.node.isHidden ? style.tertiary : style.secondary
    }

    private var label: String {
        let node = row.node
        let change = node.isFolder ? (node.change == nil ? nil : "has changes") : node.change?.spoken
        return [node.name, node.isFolder ? "folder" : nil, change].compactMap(\.self).joined(separator: ", ")
    }
}

/// The viewed file's quiet highlight (the sidebar's selection), and half of it under the pointer.
private struct FilesRowBackground: View {
    let viewed: Bool
    let hovering: Bool
    let style: SidebarStyle

    var body: some View {
        RoundedRectangle(cornerRadius: 8.scaled, style: .continuous)
            .fill(viewed ? style.selection : hovering ? style.selection.opacity(0.5) : .clear)
    }
}

private extension GitChange {
    /// For VoiceOver ("README.md, modified").
    var spoken: String {
        switch self {
        case .modified: "modified"
        case .added: "added"
        case .deleted: "deleted"
        case .renamed: "renamed"
        case .untracked: "untracked"
        }
    }
}
