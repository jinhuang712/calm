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
    /// Whether the index knows any session at all: nil until it has answered, then false only while
    /// every answer, including the first (an empty query lists the most recent), came back empty.
    /// The welcome page uses it to decide whether to show a list of sessions.
    private(set) var hasHistory: Bool?
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
                let open = sessions.first { $0.runs(transcriptPath: result.transcriptPath, agentSessionID: result.agentSessionID) }
                return Item(result: result, openSession: open?.id)
            }
            selection = min(selection, max(items.count - 1, 0))
            if !items.isEmpty {
                hasHistory = true
            } else if hasHistory == nil {
                hasHistory = false
            }
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
                HStack(spacing: 10.scaled) {
                    Image(systemName: "magnifyingglass")
                        .calmFont(size: 14)
                        .foregroundStyle(.tertiary)
                    TextField("Search every session", text: $model.query)
                        .textFieldStyle(.plain)
                        .calmFont(size: 15)
                        .focused($fieldFocused)
                        .onSubmit(openSelection)
                }
                .padding(.horizontal, 18.scaled)
                .frame(height: 48.scaled)

                Divider().opacity(0.5)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2.scaled) {
                            // Rows keep the ForEach's identity (the transcript): an `.id(index)`
                            // here made the lazy stack keep drawing the previous results' rows.
                            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                                row(item, selected: index == model.selection)
                                    .onTapGesture { onOpen(item) }
                            }
                        }
                        .padding(6.scaled)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                    }
                    .scrollIndicators(.never)
                    // Seven and a half rows: the half row says there's more below.
                    .frame(height: min(contentHeight, 6 + 7.5 * (Self.rowHeight + 2)))
                    .onChange(of: model.selection) { proxy.scrollTo(model.selectedItem?.id, anchor: .center) }
                }

                if model.items.isEmpty {
                    Text(model.query.isEmpty ? "No sessions indexed yet" : "No session mentions that")
                        .calmFont(size: 13)
                        .foregroundStyle(.secondary)
                        .frame(height: 44.scaled)
                } else if let item = model.selectedItem {
                    // What Enter does lives here, so rows keep one height as the selection moves.
                    Divider().opacity(0.5)
                    Text(action(item))
                        .calmFont(size: 11)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18.scaled)
                        .frame(height: 30.scaled)
                }
            }
            .frame(width: 620.scaled)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14.scaled, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14.scaled, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            .padding(.top, 90.scaled)
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

    @MainActor
    static var rowHeight: CGFloat {
        52.scaled
    }

    /// Two lines at one fixed height: title with project and time, then the snippet. Snippets
    /// open just before the match (SearchIndex), so one line is enough to show it.
    private func row(_ item: SearchPanelModel.Item, selected: Bool) -> some View {
        let result = item.result
        return HStack(spacing: 12.scaled) {
            AgentLogo(agent: result.agent, size: 22)
            VStack(alignment: .leading, spacing: 3.scaled) {
                HStack(spacing: 8.scaled) {
                    Text(result.title)
                        .calmFont(size: 13, weight: .medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(detail(result))
                        .calmFont(size: 11)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                Text(Self.highlighted(result.snippet))
                    .calmFont(size: 12)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 12.scaled)
        .frame(height: Self.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8.scaled, style: .continuous)
                .fill(selected ? Color.primary.opacity(0.08) : .clear),
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "api · 2h", or "api · Apr 14" once it's more than a week old.
    private func detail(_ result: SearchResult) -> String {
        let project = result.directory.map { WorkspacePath.displayName(for: $0) } ?? result.agent.displayName
        return "\(project) · \(Self.when(result.lastActive, now: Date()))"
    }

    static func when(_ date: Date, now: Date) -> String {
        let interval = now.timeIntervalSince(date)
        guard interval >= 7 * 86400 else { return RelativeTimeText.format(interval) }
        let sameYear = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
        return date.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
    }

    private func action(_ item: SearchPanelModel.Item) -> String {
        if item.openSession != nil {
            return "↵ Open"
        }
        let folder = item.result.directory.map { WorkspacePath.displayName(for: $0) } ?? "~"
        if item.result.transcriptDeleted {
            // Found through the index's copy; the agent has nothing left to resume from.
            return "↵ New session in \(folder) · \(item.result.agent.displayName) deleted this conversation, so it can't be resumed"
        }
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
