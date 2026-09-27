import CalmAgents
import CalmModel
import CalmSearch
import SwiftUI

/// ⌘K (FEATURES.md → F7, UIUX.md → Search): one field over every past and present session.
/// Results are sessions; Enter goes to the session if it's open in Calm, otherwise resumes it in
/// its project folder. The index refreshes as the panel opens, then typing only queries it.
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
                let open = sessions.first { session in
                    guard let agent = session.agent else { return false }
                    return agent.transcriptPath == result.transcriptPath
                        || result.agentSessionID != nil && agent.agentSessionID == result.agentSessionID
                }
                return Item(result: result, openSession: open?.id)
            }
            selection = min(selection, max(items.count - 1, 0))
        }
    }

    var selectedItem: Item? {
        items.indices.contains(selection) ? items[selection] : nil
    }
}

struct SearchPanelView: View {
    @Bindable var model: SearchPanelModel
    let isDark: Bool
    let onOpen: (SearchPanelModel.Item) -> Void
    let onDismiss: () -> Void

    @FocusState private var fieldFocused: Bool
    /// The results' natural height, so the panel hugs a short list instead of stretching.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                TextField("Search sessions", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .focused($fieldFocused)
                    .onSubmit(openSelection)

                Divider().opacity(0.5)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                                row(item, selected: index == model.selection)
                                    .id(index)
                                    .onTapGesture { onOpen(item) }
                            }
                        }
                        .padding(6)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                    }
                    .frame(height: min(contentHeight, 420))
                    .onChange(of: model.selection) { proxy.scrollTo(model.selection, anchor: .center) }
                }

                if model.items.isEmpty {
                    Text(model.query.isEmpty ? "No sessions indexed yet" : "No session mentions that")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(height: 44)
                }
            }
            .frame(width: 620)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            .padding(.top, 90)
        }
        .environment(\.colorScheme, isDark ? .dark : .light)
        .onAppear { fieldFocused = true }
        .onKeyPress(.downArrow) {
            model.selection = min(model.selection + 1, max(model.items.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            model.selection = max(model.selection - 1, 0)
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private func row(_ item: SearchPanelModel.Item, selected: Bool) -> some View {
        let result = item.result
        return HStack(alignment: .top, spacing: 10) {
            Text(result.agent.monogram)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(result.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(detail(result))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if !result.snippet.isEmpty {
                    Text(Self.highlighted(result.snippet))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if selected {
                    Text(action(item))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.primary.opacity(0.08) : .clear),
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "api · 2h ago".
    private func detail(_ result: SearchResult) -> String {
        let project = result.directory.map { WorkspacePath.displayName(for: $0) } ?? result.agent.displayName
        return "\(project) · \(RelativeTimeText.format(Date().timeIntervalSince(result.lastActive)))"
    }

    private func action(_ item: SearchPanelModel.Item) -> String {
        if item.openSession != nil {
            return "↵ Open"
        }
        let folder = item.result.directory.map { WorkspacePath.displayName(for: $0) } ?? "~"
        return "↵ Resume in \(folder)"
    }

    /// The snippet with its matches (between U+0002 and U+0003) in the primary color.
    static func highlighted(_ snippet: String) -> AttributedString {
        var output = AttributedString()
        var matching = false
        var current = ""
        func flush() {
            guard !current.isEmpty else { return }
            var part = AttributedString(current)
            if matching {
                part.foregroundColor = .primary
                part.font = .system(size: 12, weight: .semibold)
            }
            output += part
            current = ""
        }
        for character in snippet.replacingOccurrences(of: "\n", with: " ") {
            if character == SearchResult.matchStart || character == SearchResult.matchEnd {
                flush()
                matching = character == SearchResult.matchStart
            } else {
                current.append(character)
            }
        }
        flush()
        return output
    }

    private func openSelection() {
        if let item = model.selectedItem {
            onOpen(item)
        }
    }
}
