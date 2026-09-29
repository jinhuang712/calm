import CalmModel
import SwiftUI

/// Shrink to fit (Settings → Appearance → Session cards; UIUX.md → Session cards): the
/// sidebar's cards step down from the chosen size when its sessions don't fit without
/// scrolling, and back up when they do. `SessionCardFit` decides; this measures the list and
/// guesses the cards' heights at the other sizes.
@MainActor
@Observable
final class SidebarCardFit {
    private(set) var fit = SessionCardFit()
    /// The list's height and the room it has, as last laid out.
    @ObservationIgnored private var geometry: Geometry?
    /// For its first moment the sidebar settles without motion, so a launch with many sessions
    /// comes up at its size instead of shrinking in front of you.
    @ObservationIgnored private var settled = false
    @ObservationIgnored private var settling: Task<Void, Never>?

    struct Geometry: Equatable {
        let list: CGFloat
        let room: CGFloat

        init(_ scroll: ScrollGeometry) {
            list = scroll.contentSize.height
            room = scroll.containerSize.height
        }
    }

    /// The size to draw: the chosen one, or smaller while shrinking to fit.
    func size(largest: CalmSettings.SessionCardSize, fitting: Bool) -> CalmSettings.SessionCardSize {
        guard fitting, fit.size.rank > largest.rank else { return largest }
        return fit.size
    }

    func measured(
        _ geometry: Geometry, manager: SessionManager, renaming: Session.ID?, largest: CalmSettings.SessionCardSize, fitting: Bool,
    ) {
        self.geometry = geometry
        if settling == nil {
            // From the first layout: what's decided in the next second is the launch.
            settling = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.settled = true
            }
        }
        refit(manager: manager, renaming: renaming, largest: largest, fitting: fitting)
    }

    func refit(manager: SessionManager, renaming: Session.ID?, largest: CalmSettings.SessionCardSize, fitting: Bool) {
        guard fitting else {
            if fit.size != largest {
                fit = SessionCardFit(size: largest)
            }
            return
        }
        guard let geometry, geometry.list > 0, geometry.room > 0 else { return }
        let workspace = manager.workspace
        let open = workspace.orderedProjects.filter { !$0.isCollapsed }
        let cards = open.flatMap { workspace.sessions(in: $0.id) }.filter { $0.agent != nil && $0.id != renaming }
        let scale = Double(InterfaceScale.shared.factor)
        var next = fit
        let changed = next.update(
            largest: largest, measured: Double(geometry.list), room: Double(geometry.room),
            cards: { size in scale * cards.reduce(0) { $0 + Self.nominalHeight(of: $1, at: size) } },
            contents: Self.contents(cards, open: open.count, room: geometry.room, scale: scale),
        )
        guard changed else { return }
        Trace.note("cards fit: \(fit.size.rawValue) → \(next.size.rawValue), list \(Int(geometry.list)) in \(Int(geometry.room))")
        if settled {
            fit = next
        } else {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { fit = next }
        }
    }

    private static func nominalHeight(of session: Session, at size: CalmSettings.SessionCardSize) -> Double {
        SessionCardLayout.nominalHeight(
            size: size, state: session.state, hasRecap: session.recap != nil,
            hasProgress: (session.agent?.tail?.progress?.total ?? 0) > 0, hasWorktree: session.worktreeName != nil,
        )
    }

    /// What the fit depends on: which cards show and what they hold, and the room. A size that
    /// overflowed is tried again only once this changes.
    private static func contents(_ cards: [Session], open: Int, room: CGFloat, scale: Double) -> Int {
        var hasher = Hasher()
        for card in cards {
            hasher.combine(card.id)
            hasher.combine(card.state)
            hasher.combine(card.recap != nil)
            hasher.combine(card.agent?.tail?.progress?.total ?? 0)
            hasher.combine(card.worktreeName)
        }
        hasher.combine(open)
        hasher.combine(Int(room.rounded()))
        hasher.combine(scale)
        return hasher.finalize()
    }
}
