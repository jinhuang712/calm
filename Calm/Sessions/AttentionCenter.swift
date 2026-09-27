import CalmModel
import Foundation

/// Turns attention effects into notifications (FEATURES.md → F5). Delivery at natural
/// pauses arrives in M3.9; until then effects are only recorded.
@MainActor
final class AttentionCenter {
    static let shared = AttentionCenter()

    private(set) var pending: [Session.ID: String] = [:]

    func apply(_ effect: AttentionEffect, for id: Session.ID) {
        switch effect {
        case .none: break
        case .notify: pending[id] = SessionManager.shared.workspace.session(id)?.lastReport?.message ?? ""
        case .withdraw: pending[id] = nil
        }
    }

    func notify(_ message: String, for id: Session.ID) {
        pending[id] = message
    }
}
