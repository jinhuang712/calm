import AppKit
import CalmModel
import OSLog
import UserNotifications

/// Turns attention into macOS notifications (FEATURES.md → F5, UIUX.md → Notifications):
/// only for a session the user isn't looking at, held until a natural pause, never dropped,
/// silent, taken back when the session is visited; clicking one focuses the session.
@MainActor
final class AttentionCenter: NSObject {
    static let shared = AttentionCenter()

    private static let log = Logger(subsystem: "com.jinhuang.calm", category: "attention")

    private var queue = AttentionQueue()
    private var timer: Timer?
    private var keyMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var authorization: Task<Bool, Never>?

    /// Self-tests and unit tests never touch the real notification center: the first request
    /// would show the user a permission prompt. They log what would be delivered instead.
    private let deliversNotifications = ProcessInfo.processInfo.environment["CALM_NO_NOTIFICATIONS"] != "1"
        && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil

    func start() {
        guard keyMonitor == nil else { return }
        // Typing anywhere in Calm delays delivery (a local monitor sees keys before the terminal).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.queue.noteTyping(at: Date())
            return event
        }
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    let attention = AttentionCenter.shared
                    attention.queue.noteFocusChange(at: Date())
                    if let id = SessionManager.shared.lookingAtSessionID {
                        attention.withdraw(id)
                    }
                    attention.deliverDue()
                }
            })
        }
        if deliversNotifications {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    // MARK: Inputs

    func apply(_ effect: AttentionEffect, for id: Session.ID) {
        switch effect {
        case .none:
            break
        case .notify:
            enqueue(SessionManager.shared.workspace.session(id)?.lastReport?.message ?? SessionState.needsYou.label, for: id)
        case .withdraw:
            withdraw(id)
        }
    }

    /// `calm notify`, or a program's own desktop notification in a plain shell.
    func notify(_ message: String, for id: Session.ID) {
        enqueue(message, for: id)
    }

    /// The user switched to a session: a pause for everything else, and its own
    /// notification no longer applies.
    func sessionVisited(_ id: Session.ID) {
        queue.noteFocusChange(at: Date())
        withdraw(id)
        deliverDue()
    }

    // MARK: Delivery

    private func enqueue(_ message: String, for id: Session.ID) {
        queue.enqueue(id, message: message, at: Date())
        deliverDue()
        if !queue.pending.isEmpty, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated { AttentionCenter.shared.deliverDue() }
            }
        }
    }

    private func withdraw(_ id: Session.ID) {
        queue.withdraw(id)
        guard deliversNotifications else { return }
        let identifier = Self.identifier(for: id)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private func deliverDue() {
        for item in queue.takeDue(at: Date()) {
            deliver(item)
        }
        if queue.pending.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    private func deliver(_ item: AttentionQueue.Item) {
        let manager = SessionManager.shared
        // Still worth saying? Not if the user is looking at the session by now.
        guard let session = manager.workspace.session(item.sessionID), manager.lookingAtSessionID != item.sessionID else { return }
        let project = manager.workspace.project(session.projectID)?.name ?? ""
        Self.log.info("notify \(session.displayTitle, privacy: .public) · \(project, privacy: .public): \(item.message, privacy: .public)")
        guard deliversNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = session.displayTitle
        content.subtitle = project
        content.body = item.message
        content.threadIdentifier = item.sessionID.uuidString
        content.userInfo = ["session": item.sessionID.uuidString]
        content.sound = nil // UIUX.md: no sound by default
        let request = UNNotificationRequest(identifier: Self.identifier(for: item.sessionID), content: content, trigger: nil)
        let authorization = authorization ?? Task {
            await (try? UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
        }
        self.authorization = authorization
        Task {
            guard await authorization.value else { return }
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// One notification per session: a newer one replaces it, and visiting removes it.
    private static func identifier(for id: Session.ID) -> String {
        "calm.session.\(id.uuidString)"
    }
}

extension AttentionCenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
    ) async {
        guard let value = response.notification.request.content.userInfo["session"] as? String,
              let id = UUID(uuidString: value)
        else { return }
        await MainActor.run {
            NSApp.activate()
            TerminalWindowManager.shared.openMainWindow().select(id)
        }
    }

    /// Calm may be the active app while the session that needs you isn't on screen.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
