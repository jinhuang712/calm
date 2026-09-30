import AppKit
import CalmAgents
import CalmModel
import CalmSearch
import SwiftUI

/// ⌘K's panel (UIUX.md → Search): the field, then the results in groups drawn like the sidebar's,
/// in the chrome's own colors and a session card's type sizes, all grown with the interface size.
struct SearchPanelView: View {
    @Bindable var model: SearchModel
    let style: SidebarStyle
    /// A step off the terminal's background, like the link tag: the panel floats over the session.
    let surface: Color
    let onOpen: (SearchPanelModel.Item) -> Void
    let onDismiss: () -> Void

    @FocusState private var fieldFocused: Bool
    @State private var caret: TextSelection?
    @State private var scroll = ScrollState()
    @State private var position = ScrollPosition()
    /// Where each row's bottom falls in the list (not the headers'), so the list can end on a whole row.
    @State private var bottoms: [AnyHashable: CGFloat] = [:]
    @State private var tops: [AnyHashable: CGFloat] = [:]
    /// A group's last row as it opened five more: where it stood in the list's window, so it can
    /// stay under the pointer while the rows come in above it.
    @State private var holding: (id: AnyHashable, y: CGFloat)?
    /// The last "more" this view has taken its place for.
    @State private var heldMore = 0

    /// 680 points at the standard interface size, narrower in a small window.
    private static let width: CGFloat = 680
    /// The most the list takes before it scrolls: about nine rows with their lines.
    private static let listHeight: CGFloat = 560
    /// Read in geometry closures, which run off the main actor.
    private nonisolated static let space = "search-results"

    private struct ScrollState: Equatable {
        var offset: CGFloat = 0
        var viewport: CGFloat = 0
        var content: CGFloat = 0

        var moreBelow: Bool {
            content - offset - viewport > 2
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)
                panel(in: proxy.size)
                    .padding(.top, 90.scaled)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .environment(\.colorScheme, style.isDark ? .dark : .light)
        .onAppear { fieldFocused = true }
        .onKeyPress(.downArrow) {
            model.step(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            model.step(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) { choose(.less) }
        .onKeyPress(.leftArrow) { choose(.more) }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private func panel(in size: CGSize) -> some View {
        let width = min(Self.width.scaled, size.width - 24.scaled)
        let limit = max(min(Self.listHeight.scaled, size.height - 90.scaled - 56.scaled - 40.scaled), 120.scaled)
        return VStack(spacing: 0) {
            field
            Rectangle()
                .fill(style.primary.opacity(0.07))
                .frame(height: 1)
            if model.sections.isEmpty {
                quietLine
            } else {
                list(limit: limit)
            }
        }
        .frame(width: width)
        .background(surface, in: RoundedRectangle(cornerRadius: 14.scaled, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14.scaled, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14.scaled, style: .continuous).strokeBorder(style.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        // The text under a title: the panel less the list's and row's insets, the mark and its gap.
        .onChange(of: width, initial: true) { _, width in
            model.textWidth = width / InterfaceScale.shared.factor - 74
        }
    }

    // MARK: Field

    private var field: some View {
        HStack(spacing: 10.scaled) {
            Image(systemName: "magnifyingglass")
                .calmFont(size: 15)
                .foregroundStyle(style.tertiary)
            TextField("", text: $model.query, selection: $caret, prompt: Text("Search sessions").foregroundStyle(style.tertiary))
                .textFieldStyle(.plain)
                .calmFont(size: 17)
                .foregroundStyle(style.primary)
                .tint(style.accent)
                .focused($fieldFocused)
                .onSubmit { open(nil) }
                // ⇥ and ⇧⇥ jump between groups; the field has no other use for them.
                .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")]) { press in
                    model.jump(press.modifiers.contains(.shift) || press.key == KeyEquivalent("\u{19}") ? -1 : 1)
                    return .handled
                }
                .accessibilityLabel("Search sessions")
        }
        .padding(.horizontal, 18.scaled)
        .frame(height: 56.scaled)
    }

    /// Where there are no rows: what would have been there.
    private var quietLine: some View {
        let text = if !model.answered {
            ""
        } else if !model.terms.isEmpty {
            "No session mentions that"
        } else if model.hasSessions {
            "Your recent sessions are all open"
        } else {
            "No sessions indexed yet"
        }
        return Text(text)
            .calmFont(size: 13)
            .foregroundStyle(style.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 60.scaled)
    }

    // MARK: List

    private func list(limit: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1.scaled, pinnedViews: [.sectionHeaders]) {
                    ForEach(model.sections) { section in
                        Section {
                            ForEach(section.rows) { row in
                                sessionRow(row)
                            }
                            if let tail = section.tail {
                                tailRow(section, tail)
                            }
                        } header: {
                            header(section)
                        }
                    }
                }
                .padding(.horizontal, 6.scaled)
                .padding(.bottom, 12.scaled)
                .coordinateSpace(.named(Self.space))
            }
            .scrollIndicators(.never)
            .scrollPosition($position)
            .onScrollGeometryChange(for: ScrollState.self) { geometry in
                ScrollState(offset: geometry.contentOffset.y, viewport: geometry.containerSize.height, content: geometry.contentSize.height)
            } action: { _, state in
                scroll = state
            }
            .frame(height: height(limit: limit))
            .mask {
                // A faded hint of the next row, while there is one.
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: scroll.moreBelow ? 16.scaled : 0)
                }
            }
            .onChange(of: model.generation) {
                bottoms = [:]
                tops = [:]
                position.scrollTo(edge: .top)
            }
            .onChange(of: model.selection) { old, new in
                reveal(new, from: old, proxy: proxy)
            }
            .onChange(of: model.moreRequest.count) {
                // Before the new rows are laid out, `tops` still has where the row stood.
                guard let key = model.moreRequest.key else { return }
                let id = Self.viewID(.more(key))
                heldMore = model.moreRequest.count
                holding = (id, (tops[id] ?? scroll.offset) - scroll.offset)
            }
            .onChange(of: model.headerRequest.count) {
                if let key = model.headerRequest.key {
                    proxy.scrollTo(Self.headerID(key), anchor: .top)
                }
            }
        }
    }

    /// Ends on a whole row: never half a row, and never a header with nothing under it.
    private func height(limit: CGFloat) -> CGFloat {
        guard scroll.content > limit else { return max(scroll.content, 1) }
        let inset = 12.scaled
        return bottoms.values.filter { $0 + inset <= limit }.max().map { $0 + inset } ?? limit
    }

    /// Keeps the selected row in sight, a row of room past it in the direction of travel, which
    /// also keeps it clear of the header pinned at the top.
    private func reveal(_ entry: SearchModel.Entry?, from old: SearchModel.Entry?, proxy: ScrollViewProxy) {
        guard let entry, let index = model.entries.firstIndex(of: entry), holding == nil else { return }
        // A group's last row that just opened five more stays where it is (see `holding`).
        if entry.isTail, model.moreRequest.count != heldMore {
            return
        }
        if index == 0 {
            position.scrollTo(edge: .top)
            return
        }
        let down = old.flatMap { model.entries.firstIndex(of: $0) }.map { $0 < index } ?? true
        let beyond = down ? min(index + 1, model.entries.count - 1) : index - 1
        proxy.scrollTo(Self.viewID(model.entries[beyond]))
    }

    private func sessionRow(_ row: SearchModel.Row) -> some View {
        let entry = SearchModel.Entry.session(row.id)
        return Button {
            open(entry)
        } label: {
            SearchResultRow(row: row, lines: model.lines(for: row), terms: model.terms, isSelected: model.selection == entry, style: style)
        }
        .buttonStyle(.plain)
        .id(Self.viewID(entry))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frame in
            bottoms[Self.viewID(entry)] = frame.maxY
        }
    }

    private func header(_ section: SearchModel.Section) -> some View {
        SearchGroupHeader(section: section, terms: model.terms, style: style) {
            model.fold(section.group.key)
            fieldFocused = true
        }
        .background(surface)
        .id(Self.headerID(section.group.key))
    }

    private func tailRow(_ section: SearchModel.Section, _ entry: SearchModel.Entry) -> some View {
        let id = Self.viewID(entry)
        return SearchTailRow(
            section: section, entry: entry, isSelected: model.selection == entry, side: model.side, style: style,
        ) { side in
            open(entry, side: side)
        }
        .id(id)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frame in
            bottoms[id] = frame.maxY
            tops[id] = frame.minY
            // Rows came in above it: move the list by as much, so it stays under the pointer.
            if let holding, holding.id == id {
                self.holding = nil
                position.scrollTo(y: max(frame.minY - holding.y, 0))
            }
        }
    }

    // MARK: Actions

    private func open(_ entry: SearchModel.Entry?, side: SearchModel.Side? = nil) {
        if let entry {
            model.select(entry)
        }
        if let item = model.activate(entry, side: side) {
            onOpen(item)
        }
        fieldFocused = true
    }

    /// → and ← on an opened group's last row choose its half. Inside the field they move the
    /// caret, until it is at the text's end or the arrows have been used, as on the welcome page.
    private func choose(_ side: SearchModel.Side) -> KeyPress.Result {
        if side == .less, fieldFocused, !model.navigated, !caretAtEnd {
            return .ignored
        }
        return model.choose(side) ? .handled : .ignored
    }

    private var caretAtEnd: Bool {
        if model.query.isEmpty {
            return true
        }
        guard case let .selection(range)? = caret?.indices, range.isEmpty else { return false }
        return range.upperBound == model.query.endIndex
    }

    /// The last row of a group keeps one identity as it goes from "more" to "all", so opening the
    /// last five doesn't lose its place.
    static func viewID(_ entry: SearchModel.Entry) -> AnyHashable {
        switch entry {
        case let .session(id): AnyHashable(id)
        case let .more(key), let .all(key): AnyHashable(["tail", "\(key)"])
        }
    }

    static func headerID(_ key: SearchGroup.Key) -> AnyHashable {
        AnyHashable(["header", "\(key)"])
    }

    // MARK: Text

    /// `text` with every match of `terms` marked: a soft wash of the accent, in the primary color.
    static func marked(_ text: String, terms: [String], size: CGFloat, style: SidebarStyle) -> AttributedString {
        var output = AttributedString(text)
        for range in SearchMatch.ranges(of: terms, in: text) {
            guard let lower = AttributedString.Index(range.lowerBound, within: output),
                  let upper = AttributedString.Index(range.upperBound, within: output) else { continue }
            output[lower ..< upper].foregroundColor = style.primary
            output[lower ..< upper].backgroundColor = style.accent.opacity(0.24)
            output[lower ..< upper].font = .system(size: size * InterfaceScale.shared.factor, weight: .medium)
        }
        return output
    }

    /// "api · 2h", or "api · Apr 14" once it's more than a week old (the welcome page's rows).
    static func when(_ date: Date, now: Date) -> String {
        let interval = now.timeIntervalSince(date)
        guard interval >= 7 * 86400 else { return RelativeTimeText.format(interval) }
        let sameYear = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
        return date.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
    }

    /// The snippet with its matches (between U+0002 and U+0003) in the primary color, as the
    /// welcome page's rows show it.
    static func highlighted(_ snippet: String) -> AttributedString {
        var output = AttributedString()
        var matching = false
        var current = ""
        func flush() {
            guard !current.isEmpty else { return }
            var part = AttributedString(current)
            if matching {
                part.foregroundColor = .primary
                // Grown with the interface size like the text around it.
                part.font = .system(size: 12 * InterfaceScale.shared.factor, weight: .semibold)
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
}

// MARK: - Rows

/// A result: the agent's mark, the title with its time (or, open in Calm, its state's mark), and
/// under it the lines that show the words searched for. Your own lines hang the prompt's chevron
/// in the gutter; the agent's have nothing, so every line starts under the title.
private struct SearchResultRow: View {
    let row: SearchModel.Row
    let lines: [SearchModel.Line]
    let terms: [String]
    let isSelected: Bool
    let style: SidebarStyle
    @State private var hovering = false

    private var result: SearchResult {
        row.item.result
    }

    var body: some View {
        let typing = !terms.isEmpty
        HStack(alignment: typing ? .top : .center, spacing: 12.scaled) {
            AgentLogo(agent: result.agent, size: 26, style: style)
                // Level with the title's line.
                .offset(y: typing ? -3.scaled : 0)
            VStack(alignment: .leading, spacing: 4.scaled) {
                HStack(spacing: 10.scaled) {
                    Text(title)
                        .calmFont(size: 14.5, weight: .medium)
                        .foregroundStyle(style.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8.scaled)
                    trailing
                    if isSelected {
                        KeyCaps(keys: ["↵"], style: style)
                    }
                }
                .frame(height: 20.scaled)
                ForEach(lines) { line in
                    Text(text(of: line))
                        .calmFont(size: 13)
                        .foregroundStyle(style.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .leading) {
                            if line.fromYou {
                                Image(systemName: "chevron.right")
                                    .calmFont(size: 8.5, weight: .bold)
                                    .foregroundStyle(style.tertiary)
                                    .frame(width: 11.scaled)
                                    .offset(x: -12.scaled)
                                    .help("You")
                            }
                        }
                }
            }
        }
        .padding(.horizontal, 12.scaled)
        .padding(.vertical, typing ? 11.scaled : 0)
        .frame(maxWidth: .infinity, minHeight: typing ? nil : 42.scaled, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10.scaled, style: .continuous).fill(
            isSelected ? style.selection : hovering ? style.primary.opacity(0.04) : .clear,
        ))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityElement(children: .combine)
    }

    private var title: AttributedString {
        var title = SearchPanelView.marked(result.title, terms: terms, size: 14.5, style: style)
        if result.transcriptDeleted {
            var note = AttributedString(" · can’t be resumed")
            note.foregroundColor = style.tertiary
            note.font = .system(size: 13 * InterfaceScale.shared.factor)
            title += note
        }
        return title
    }

    /// Open in Calm: its state's mark, as in the sidebar. Otherwise how long ago, written out,
    /// the figures a step brighter.
    @ViewBuilder
    private var trailing: some View {
        if let state = row.state {
            StateMark(state: state, style: style, compact: true)
                .help("\(state.label) · open in Calm")
        } else {
            Text(WrittenTime.runs(WrittenTime.text(since: result.lastActive)).reduce(into: AttributedString()) { text, run in
                var part = AttributedString(run.text)
                part.foregroundColor = run.isNumber ? style.secondary : style.tertiary
                text += part
            })
            .calmFont(size: 12)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
        }
    }

    private func text(of line: SearchModel.Line) -> AttributedString {
        var output = AttributedString()
        for (index, part) in line.parts.enumerated() {
            switch part {
            case let .text(text):
                output += SearchPanelView.marked(text, terms: terms, size: 13, style: style)
            case .gap:
                var gap = AttributedString(index == 0 ? "… " : " … ")
                gap.foregroundColor = style.tertiary
                output += gap
            }
        }
        return output
    }

    private var help: String {
        let folder = result.directory.map { WorkspacePath.abbreviated($0) } ?? "~"
        if row.item.openSession != nil {
            return "Go to this session"
        }
        if result.transcriptDeleted {
            return "New session in \(folder) · \(result.agent.displayName) deleted this conversation, so it can’t be resumed"
        }
        return "Resume in \(folder)"
    }
}

/// A group's header, pinned while its rows scroll under it: the sidebar's mark and name, then what
/// it holds as three counts at most (open, idle, and past on the project's own tile), and, once
/// opened past its share, a chevron that folds it back.
private struct SearchGroupHeader: View {
    let section: SearchModel.Section
    let terms: [String]
    let style: SidebarStyle
    let fold: () -> Void

    private var group: SearchGroup {
        section.group
    }

    var body: some View {
        HStack(spacing: 12.scaled) {
            Group {
                if let project = group.project {
                    GroupMark(project: project, style: style)
                } else {
                    Image(systemName: "folder")
                        .calmFont(size: 12)
                }
            }
            .foregroundStyle(style.tertiary)
            .frame(width: 26.scaled)
            name
            Spacer(minLength: 8.scaled)
            if let counts = section.counts {
                SearchCounts(counts: counts, colors: colors, style: style)
            }
            if section.folds {
                Button(action: fold) {
                    Image(systemName: "chevron.up")
                        .calmFont(size: 10, weight: .semibold)
                        .foregroundStyle(style.tertiary)
                        .frame(width: 22.scaled, height: 20.scaled)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show less")
                .accessibilityLabel("Show less in \(group.name)")
            }
        }
        .padding(.horizontal, 12.scaled)
        .padding(.top, 10.scaled)
        .frame(height: 42.scaled)
        .help(section.counts?.words ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// As the sidebar writes it: a folder's own name as it is on disk, a project's in small capitals.
    @ViewBuilder
    private var name: some View {
        if group.project?.kind == .directory || group.project == nil {
            Text(SearchPanelView.marked(group.name, terms: terms, size: 13.5, style: style))
                .calmFont(size: 13.5, weight: .medium)
                .foregroundStyle(style.secondary)
                .lineLimit(1)
        } else {
            Text(SearchPanelView.marked(group.name.uppercased(), terms: terms, size: 12, style: style))
                .calmFont(size: 12, weight: .semibold)
                .tracking(0.7)
                .foregroundStyle(style.tertiary)
                .lineLimit(1)
        }
    }

    /// A project's numbers wear its mark's colors; other groups' are the chrome's grays.
    private var colors: (ink: Color, tile: Color) {
        guard let project = group.project, project.kind == .project else { return (style.secondary, style.primary.opacity(0.07)) }
        return IdenticonTile.colors(of: Identicon(name: project.name, seed: project.markSeed), style: style)
    }
}

/// Open (the working ring, blue), idle (the gray dot) and past (the project's tile), each only
/// when it isn't zero: the same width for 5 sessions or 500.
private struct SearchCounts: View {
    let counts: SearchGroupCounts
    let colors: (ink: Color, tile: Color)
    let style: SidebarStyle

    var body: some View {
        HStack(spacing: 10.scaled) {
            if counts.open > 0 {
                HStack(spacing: 4.scaled) {
                    StateMark(state: .working, style: style, compact: true)
                    Text("\(counts.open)")
                        .calmFont(size: 13, weight: .medium)
                        .foregroundStyle(style.working)
                }
            }
            if counts.idle > 0 {
                HStack(spacing: 4.scaled) {
                    StateMark(state: .idle, style: style, compact: true)
                    Text("\(counts.idle)")
                        .calmFont(size: 13, weight: .medium)
                        .foregroundStyle(style.tertiary)
                }
            }
            if counts.past > 0 {
                Text("\(counts.past)")
                    .calmFont(size: 12, weight: .semibold)
                    .foregroundStyle(colors.ink)
                    .padding(.horizontal, 6.scaled)
                    .frame(minWidth: 24.scaled, minHeight: 20.scaled)
                    .background(RoundedRectangle(cornerRadius: 4.5.scaled, style: .continuous).fill(colors.tile))
            }
        }
        .monospacedDigit()
        .fixedSize()
    }
}

/// A group's last row: "13 more in calm" shows five more; once opened, Show less on its right
/// folds it back. With all of it showing, "All 16 in calm" (nothing to click there, so a click too
/// many never folds it by surprise) and Show less.
private struct SearchTailRow: View {
    let section: SearchModel.Section
    let entry: SearchModel.Entry
    let isSelected: Bool
    let side: SearchModel.Side
    let style: SidebarStyle
    let act: (SearchModel.Side) -> Void
    @State private var hovering = false

    private var isAll: Bool {
        if case .all = entry {
            return true
        }
        return false
    }

    private var onLess: Bool {
        isSelected && (isAll || side == .less)
    }

    var body: some View {
        HStack(spacing: 12.scaled) {
            Image(systemName: "chevron.down")
                .calmFont(size: 10, weight: .semibold)
                .foregroundStyle(style.tertiary)
                .frame(width: 26.scaled)
                .opacity(isAll ? 0 : 1)
            if isAll {
                Text("All \(section.total) in \(section.group.name)")
                    .foregroundStyle(style.tertiary)
                    .lineLimit(1)
            } else {
                Button {
                    act(.more)
                } label: {
                    Text(moreText)
                        .foregroundStyle(isSelected && !onLess ? style.primary : style.secondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                if isSelected, !onLess {
                    KeyCaps(keys: ["↵"], style: style)
                }
            }
            Spacer(minLength: 8.scaled)
            if section.folds {
                Button {
                    act(.less)
                } label: {
                    HStack(spacing: 6.scaled) {
                        Text("Show less")
                        Image(systemName: "chevron.up")
                            .calmFont(size: 9, weight: .semibold)
                    }
                    .foregroundStyle(onLess ? style.primary : style.tertiary)
                }
                .buttonStyle(.plain)
                if onLess {
                    KeyCaps(keys: ["↵"], style: style)
                }
            }
        }
        .calmFont(size: 13)
        .padding(.horizontal, 12.scaled)
        .frame(height: 38.scaled)
        .background(RoundedRectangle(cornerRadius: 10.scaled, style: .continuous).fill(
            isSelected ? style.selection : hovering ? style.primary.opacity(0.04) : .clear,
        ))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    /// The number in the project's own ink, the words in the secondary gray.
    private var moreText: AttributedString {
        var number = AttributedString("\(section.more)")
        number.font = .system(size: 13 * InterfaceScale.shared.factor, weight: .semibold)
        if let project = section.group.project, project.kind == .project {
            number.foregroundColor = IdenticonTile.colors(of: Identicon(name: project.name, seed: project.markSeed), style: style).ink
        } else {
            number.foregroundColor = style.primary
        }
        return number + AttributedString(" more in \(section.group.name)")
    }
}
