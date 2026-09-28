import AppKit
import CalmModel
import SwiftUI

/// The files column (FEATURES.md → F10): the focused session's project, right of the sidebar;
/// git-ignored files hidden, changed files marked; ⌘\ toggles it; a click opens the viewer.
@MainActor
@Observable
final class FilesModel {
    var root: String?
    /// Set while `root` is a scratch session's folder.
    var isScratch = false
    var branch: String?
    var nodes: [FileNode] = []
    var changedCount = 0
    var style = SidebarStyle.derived(from: NSColor(white: 0.12, alpha: 1))
    var viewedFile: String?
    var onOpen: (String) -> Void = { _ in }
    private var loading: Task<Void, Never>?

    /// Opens a file of the tree (a path relative to `root`) in the viewer.
    func open(_ path: String) {
        guard let root else { return }
        onOpen((root as NSString).appendingPathComponent(path))
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
            changedCount = 0
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
            changedCount = listing.changes.count
        }
    }
}

/// Reads a folder's files: through git when it's in a repository (ignored files left out,
/// changes marked), else a bounded walk of the folder.
enum FilesListing {
    struct Result {
        var paths: [String] = []
        var changes: [String: GitChange] = [:]
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
        result.branch = git(["branch", "--show-current"], in: root)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
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
    static let width: CGFloat = 240
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
}

struct FilesColumnView: View {
    let model: FilesModel

    var body: some View {
        let style = model.style
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2.scaled) {
                Text(model.title)
                    .calmFont(size: 12, weight: .medium)
                    .foregroundStyle(style.primary)
                    .lineLimit(1)
                if let branch = model.branch, !branch.isEmpty {
                    Text(model.changedCount > 0 ? "\(branch) · \(model.changedCount) Δ" : branch)
                        .calmFont(size: 11)
                        .foregroundStyle(style.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14.scaled)
            .padding(.top, 40.scaled)
            .padding(.bottom, 8.scaled)

            // Files are buttons rather than selected rows: the list's own selection is the system
            // accent, louder than the sidebar's quiet highlight. Buttons also reach the keyboard
            // (Full Keyboard Access) and VoiceOver.
            List(model.nodes, children: \.children) { node in
                Group {
                    if node.isFolder {
                        row(node, style: style)
                    } else {
                        Button { model.open(node.path) } label: {
                            row(node, style: style).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .accessibilityLabel(accessibilityLabel(node))
                .listRowBackground(
                    isViewed(node) ? RoundedRectangle(cornerRadius: 5.scaled).fill(style.selection).padding(.horizontal, 8.scaled) : nil,
                )
            }
            .listStyle(.sidebar)
            .environment(\.sidebarRowSize, .small)
            .scrollContentBackground(.hidden)
        }
        .frame(width: FilesColumn.width)
        .frame(maxHeight: .infinity, alignment: .top)
        // Under the title bar too, like the sidebar.
        .background(style.background.opacity(0.94 * style.surfaceOpacity).ignoresSafeArea())
        .overlay(alignment: .leading) { Rectangle().fill(style.tertiary.opacity(0.18)).frame(width: 1).ignoresSafeArea() }
        // Laid out at full width and clipped while the column slides, never squeezed.
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, style.isDark ? .dark : .light)
    }

    private func accessibilityLabel(_ node: FileNode) -> String {
        let change: String? = switch node.change {
        case .modified: node.isFolder ? "has changes" : "modified"
        case .added: "added"
        case .deleted: "deleted"
        case .renamed: "renamed"
        case .untracked: "untracked"
        case nil: nil
        }
        return ([node.name, node.isFolder ? "folder" : nil, change].compactMap(\.self)).joined(separator: ", ")
    }

    private func isViewed(_ node: FileNode) -> Bool {
        model.root.map { ($0 as NSString).appendingPathComponent(node.path) } == model.viewedFile
    }

    private func row(_ node: FileNode, style: SidebarStyle) -> some View {
        let viewed = isViewed(node)
        return HStack(spacing: 6.scaled) {
            Text(node.name)
                .calmFont(size: 12, weight: viewed ? .medium : .regular)
                .foregroundStyle(viewed ? style.primary : style.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if let change = node.change, !node.isFolder {
                Text(change.rawValue)
                    .calmFont(size: 10, weight: .medium, design: .monospaced)
                    .foregroundStyle(change == .deleted ? style.failure : style.tertiary)
            } else if node.change != nil {
                Circle().fill(style.tertiary).frame(width: 4.scaled, height: 4.scaled)
            }
        }
    }
}
