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
    private var leaving = LeavingCalm(calmIsActive: true)

    /// Self-tests and unit tests never touch the real notification center: the first request
    /// would show the user a permission prompt. They log what would be delivered instead.
    static let deliversNotifications = ProcessInfo.processInfo.environment["CALM_NO_NOTIFICATIONS"] != "1"
        && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil

    func start() {
        guard keyMonitor == nil else { return }
        // Typing anywhere in Calm delays delivery (a local monitor sees keys before the terminal).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.queue.noteTyping(at: Date())
            return event
        }
        leaving = LeavingCalm(calmIsActive: NSApp.isActive)
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    if name == NSApplication.didBecomeActiveNotification {
                        AttentionCenter.shared.leaving.calmCameForward()
                    }
                    let attention = AttentionCenter.shared
                    attention.queue.noteFocusChange(at: Date())
                    if let id = SessionManager.shared.lookingAtSessionID {
                        attention.withdraw(id)
                    }
                    attention.deliverDue()
                }
            })
        }
        // Calm losing the front isn't enough to have left it: a menu-bar tool in front for a
        // moment isn't leaving, so the app that comes forward decides (LeavingCalm).
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main,
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let processID = app?.processIdentifier
            let regular = app?.activationPolicy == .regular
            MainActor.assumeIsolated {
                AttentionCenter.shared.appCameForward(processID: processID, regular: regular)
            }
        })
        if Self.deliversNotifications {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    // MARK: Inputs

    /// An app came to the front; `regular` when it has a Dock icon. Leaving Calm for it settles
    /// the session the user saw there, as going to another session does.
    func appCameForward(processID: pid_t?, regular: Bool) {
        let manager = SessionManager.shared
        if processID == ProcessInfo.processInfo.processIdentifier {
            leaving.calmCameForward()
        } else if let left = leaving.appCameForward(regular: regular, onScreen: manager.onScreen) {
            manager.settle(left: left)
        }
    }

    func apply(_ effect: AttentionEffect, for id: Session.ID) {
        switch effect {
        case .none:
            break
        case .notify:
            enqueue(SessionManager.shared.workspace.session(id)?.lastReport?.message, state: .needsYou, for: id)
        case .withdraw:
            withdraw(id)
        }
    }

    /// A state worth a notification when it's opted into (done, failed), or `calm notify`, or a
    /// program's own desktop notification in a plain shell (no state, so no mark in the title).
    func notify(_ message: String?, state: SessionState? = nil, for id: Session.ID) {
        enqueue(message, state: state, for: id)
    }

    /// The user switched to a session: a pause for everything else, and its own
    /// notification no longer applies.
    func sessionVisited(_ id: Session.ID) {
        queue.noteFocusChange(at: Date())
        withdraw(id)
        deliverDue()
    }

    // MARK: Delivery

    private func enqueue(_ message: String?, state: SessionState?, for id: Session.ID) {
        queue.enqueue(id, message: message, state: state, at: Date())
        deliverDue()
        if !queue.pending.isEmpty, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated { AttentionCenter.shared.deliverDue() }
            }
        }
    }

    private func withdraw(_ id: Session.ID) {
        queue.withdraw(id)
        guard Self.deliversNotifications else { return }
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
        // No subtitle: Calm's icon says where it's from, and the session's name says which one.
        let text = NotificationText(state: item.state, sessionName: session.displayTitle, message: item.message)
        Self.log.info("notify \(text.title, privacy: .public): \(text.body, privacy: .public)")
        guard Self.deliversNotifications else {
            // Self-tests read what would have been shown from their log.
            FileHandle.standardError.write(Data("calm-selftest: notification \(text.title) | \(text.body)\n".utf8))
            return
        }

        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.threadIdentifier = item.sessionID.uuidString
        content.userInfo = ["session": item.sessionID.uuidString]
        content.sound = manager.settings.notificationSound ? .default : nil // UIUX.md: no sound by default
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
