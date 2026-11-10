import CalmModel
import SwiftUI

/// Shrink to fit (Settings → Appearance → Session cards; specs/UIUX.md → Session cards): the
/// sidebar's cards fold from the chosen size when its sessions don't fit without scrolling, idle
/// ones first (`CardFold`), and back up when they fit. `TieredCardFit` decides; this measures the
/// list, guesses the cards' heights at the other folds, and looks again when a wait after a step
/// down ends.
@MainActor
@Observable
final class SidebarCardFit {
    /// The fold the cards are drawn at while fitting. The only observed state, so the sidebar
    /// redraws when the fold changes and not on every measurement.
    private(set) var shown = CardFold(.full)
    /// The same for pinned cards, which fold last.
    private(set) var shownPinned = CardFold(.full)
    /// Everything the fit keeps between measurements (how tall each fold was drawn, how short
    /// guesses were, when and in what room it stepped down). Kept after every measurement,
    /// whether or not the fold changed.
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

    /// The fold to draw: every card at the chosen size, or a step down from it while shrinking to fit.
    func fold(largest: CalmSettings.SessionCardSize, fitting: Bool) -> CardFold {
        Self.fold(shown, largest: largest, fitting: fitting)
    }

    /// The fold to draw pinned cards at.
    func pinnedFold(largest: CalmSettings.SessionCardSize, fitting: Bool) -> CardFold {
        Self.fold(shownPinned, largest: largest, fitting: fitting)
    }

    /// `shown`, if it's a step down from `largest`: it can be larger for a moment after the chosen
    /// size went down.
    private static func fold(_ shown: CardFold, largest: CalmSettings.SessionCardSize, fitting: Bool) -> CardFold {
        guard fitting, CardFold.steps(from: largest).contains(shown) else { return CardFold(largest) }
        return shown
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
            show(CardFold(largest), pinned: CardFold(largest))
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
        let before = (model.otherFold, model.pinnedFold)
        model.update(
            largest: largest, measured: Double(geometry.list), room: Double(geometry.room),
            cards: { others, pinned in
                scale * cards.reduce(0) { $0 + Self.nominalHeight(of: $1, at: $1.cardSize(others: others, pinned: pinned)) }
            },
            pinnedHeight: { fold in scale * Self.pinnedHeight(of: pinned, at: fold) },
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
        if (model.otherFold, model.pinnedFold) != before {
            Trace.note(
                "cards fit: \(before.0)/\(before.1) → \(model.otherFold)/\(model.pinnedFold), "
                    + "list \(Int(geometry.list)) in \(Int(geometry.room))",
            )
        }
        show(model.otherFold, pinned: model.pinnedFold)
    }

    private func show(_ fold: CardFold, pinned: CardFold) {
        guard fold != shown || pinned != shownPinned else { return }
        if settled {
            shown = fold
            shownPinned = pinned
        } else {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                shown = fold
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
    private static func pinnedHeight(of sessions: [Session], at fold: CardFold) -> Double {
        guard !sessions.isEmpty else { return 0 }
        let rowGap = 6.0
        let rows = sessions.reduce(0) { height, session in
            let card = session.agent == nil ? 58 : nominalHeight(of: session, at: session.cardSize(others: fold, pinned: fold))
            return height + rowGap + card
        }
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
            // The state also decides whether a card folds first (`CardFold`).
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
