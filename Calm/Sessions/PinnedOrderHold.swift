import CalmModel
import Foundation

/// Keeps Pinned's order still while the pointer moves over the sidebar, so a card that a state
/// change sends elsewhere never slides out from under a click (specs/FEATURES.md → F2). It lasts
/// until the pointer leaves or rests: a pointer parked on the sidebar during typing holds nothing.
@MainActor
@Observable
final class PinnedOrderHold {
    private(set) var order: [Session.ID]?
    @ObservationIgnored private var release: Task<Void, Never>?
    @ObservationIgnored private let rest: Duration

    init(rest: Duration = .seconds(1.5)) {
        self.rest = rest
    }

    /// The pointer moved over the sidebar: `current` is Pinned's order on screen.
    func pointerMoved(current: @autoclosure () -> [Session.ID]) {
        if order == nil {
            order = current()
        }
        release?.cancel()
        release = Task { [weak self, rest] in
            try? await Task.sleep(for: rest)
            guard !Task.isCancelled else { return }
            self?.end()
        }
    }

    func pointerLeft() {
        end()
    }

    private func end() {
        release?.cancel()
        release = nil
        guard order != nil else { return }
        Motion.animate { order = nil }
    }
}
