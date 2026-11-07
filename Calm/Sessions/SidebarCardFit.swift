import CalmModel
import SwiftUI

/// Shrink to fit (Settings → Appearance → Session cards; specs/UIUX.md → Session cards): the
/// sidebar's cards step down from the chosen size when its sessions don't fit without
/// scrolling, and back up when they do. `SessionCardFit` decides; this measures the list,
/// guesses the cards' heights at the other sizes, and looks again when a wait after a step down
/// ends.
@MainActor
@Observable
final class SidebarCardFit {
    /// The size the cards are drawn at while fitting. The only observed state, so the sidebar
    /// redraws when the size changes and not on every measurement.
    private(set) var shown = CalmSettings.SessionCardSize.full
    /// The same for pinned cards, which step down last.
    private(set) var shownPinned = CalmSettings.SessionCardSize.full
    /// Everything the fit keeps between measurements (how tall each size was drawn, how short
    /// guesses were, when and in what room it stepped down). Kept after every measurement,
    /// whether or not the size changed.
    @ObservationIgnored private var model: TieredCardFit?
    /// The list's height and the room it has, as last laid out.
    @ObservationIgnored private var geometry: Geometry?
    /// For its first moment the sidebar settles without motion, so a launch with many sessions
    /// comes up at its size instead of shrinking in front of you.
    @ObservationIgnored private var settled = false
    @ObservationIgnored private var settling: Task<Void, Never>?
    /// A look once the cards may step back up: nothing else may change by then to trigger one.
    @ObservationIgnored private var recheck: Task<Void, Never>?

    struct Geometry: Equatable {
        let list: CGFloat
        let room: CGFloat

        init(_ scroll: ScrollMetrics) {
            list = scroll.content
            room = scroll.viewport
        }
    }

    /// The size to draw: the chosen one, or smaller while shrinking to fit.
    func size(largest: CalmSettings.SessionCardSize, fitting: Bool) -> CalmSettings.SessionCardSize {
        guard fitting, shown.rank > largest.rank else { return largest }
        return shown
    }

    /// The size to draw pinned cards at.
    func pinnedSize(largest: CalmSettings.SessionCardSize, fitting: Bool) -> CalmSettings.SessionCardSize {
        guard fitting, shownPinned.rank > largest.rank else { return largest }
        return shownPinned
    }

    func measured(
        _ geometry: Geometry, manager: SessionManager, largest: CalmSettings.SessionCardSize, fitting: Bool,
    ) {
        self.geometry = geometry
        if settling == nil {
            // From the first layout: what's decided in the next second is the launch.
            settling = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.settled = true
            }
        }
        refit(manager: manager, largest: largest, fitting: fitting)
    }

    func refit(manager: SessionManager, largest: CalmSettings.SessionCardSize, fitting: Bool) {
        guard fitting else {
            model = nil
            recheck?.cancel()
            show(largest, pinned: largest)
            return
        }
        guard let geometry, geometry.list > 0, geometry.room > 0 else { return }
        let workspace = manager.workspace
        let open = workspace.sidebarProjects.filter { !$0.isCollapsed }
        let pinned = workspace.pinnedIsCollapsed == true ? [] : workspace.pinnedSessions
        let rows = pinned + open.flatMap { workspace.unpinnedSessions(in: $0.id) }
        let cards = rows.filter { $0.agent != nil }
        let scale = Double(InterfaceScale.shared.factor)
        let now = ProcessInfo.processInfo.systemUptime
        var model = model ?? TieredCardFit(size: largest)
        let before = (model.otherSize, model.pinnedSize)
        model.update(
            largest: largest, measured: Double(geometry.list), room: Double(geometry.room),
            cards: { others, pinned in
                scale * cards.reduce(0) { $0 + Self.nominalHeight(of: $1, at: $1.cardSize(others: others, pinned: pinned)) }
            },
            pinnedHeight: { size in scale * Self.pinnedHeight(of: pinned, at: size) },
            contents: Self.contents(
                rows: rows, cards: cards, groups: workspace.sidebarProjects.count + (workspace.pinnedSessions.isEmpty ? 0 : 1),
                open: open.count + (pinned.isEmpty ? 0 : 1), scale: scale,
            ),
            now: now,
        )
        self.model = model
        recheck?.cancel()
        if let at = model.growsAgain(after: now) {
            recheck = Task { [weak self] in
                try? await Task.sleep(for: .seconds(at - now + 0.1))
                guard !Task.isCancelled else { return }
                self?.refit(manager: manager, largest: largest, fitting: fitting)
            }
        }
        if (model.otherSize, model.pinnedSize) != before {
            Trace.note(
                "cards fit: \(before.0.rawValue)/\(before.1.rawValue) → \(model.otherSize.rawValue)/\(model.pinnedSize.rawValue), "
                    + "list \(Int(geometry.list)) in \(Int(geometry.room))",
            )
        }
        show(model.otherSize, pinned: model.pinnedSize)
    }

    private func show(_ size: CalmSettings.SessionCardSize, pinned: CalmSettings.SessionCardSize) {
        guard size != shown || pinned != shownPinned else { return }
        if settled {
            shown = size
            shownPinned = pinned
        } else {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                shown = size
                shownPinned = pinned
            }
        }
    }

    private static func nominalHeight(of session: Session, at size: CalmSettings.SessionCardSize) -> Double {
        SessionCardLayout.nominalHeight(
            size: size, state: session.state, hasRecap: session.recap != nil,
            hasProgress: (session.agent?.tail?.progress?.total ?? 0) > 0, hasWorktree: session.worktreeName != nil,
            shellsRunning: session.shellsStillRunning > 0, isPinned: session.pinnedAt != nil,
        )
    }

    /// About how tall Pinned is: its header and its rows. Shell rows are the same at every size.
    private static func pinnedHeight(of sessions: [Session], at size: CalmSettings.SessionCardSize) -> Double {
        guard !sessions.isEmpty else { return 0 }
        let rowGap = 6.0
        let rows = sessions.reduce(0) { $0 + rowGap + ($1.agent == nil ? 58 : nominalHeight(of: $1, at: size)) }
        return 26 + rows
    }

    /// What the list's height depends on besides the card size: the rows, what the cards hold,
    /// the groups and the interface size. A size drawn with the same contents is as tall again.
    private static func contents(rows: [Session], cards: [Session], groups: Int, open: Int, scale: Double) -> Int {
        var hasher = Hasher()
        // Shell rows are one height at every size.
        for row in rows {
            hasher.combine(row.id)
        }
        for card in cards {
            hasher.combine(card.id)
            hasher.combine(card.state)
            hasher.combine(card.recap != nil)
            hasher.combine(card.agent?.tail?.progress?.total ?? 0)
            hasher.combine(card.worktreeName)
            // An idle card with shells running has a line more at Compact.
            hasher.combine(card.shellsStillRunning > 0)
        }
        hasher.combine(groups)
        hasher.combine(open)
        hasher.combine(scale)
        return hasher.finalize()
    }
}
