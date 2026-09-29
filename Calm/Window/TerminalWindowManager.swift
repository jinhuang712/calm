import AppKit

/// Keeps the main window and answers app-level engine requests.
@MainActor
final class TerminalWindowManager: TerminalEngineDelegate {
    static let shared = TerminalWindowManager()
    private(set) var mainController: MainWindowController?

    var focusedController: MainWindowController? {
        mainController
    }

    var controllers: [MainWindowController] {
        mainController.map { [$0] } ?? []
    }

    @discardableResult
    func openMainWindow() -> MainWindowController {
        if let mainController {
            mainController.showAndFocus()
            return mainController
        }
        let controller = MainWindowController(manager: SessionManager.shared)
        mainController = controller
        controller.showAndFocus()
        controller.restoreFullScreen()
        return controller
    }

    // MARK: TerminalEngineDelegate

    func engineRequestsNewWindow(inheriting surface: TerminalSurfaceView?) {
        // One calm window: a "new window" is a new session.
        openMainWindow().newSession(inheriting: surface)
    }

    func engineRequestsQuit() {
        NSApp.terminate(nil)
    }
}
