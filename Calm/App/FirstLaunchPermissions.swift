import AppKit
import Foundation

/// The first launch asks for everything Calm will need, one prompt after another, so none
/// arrives in the middle of work: a notification when an agent needs you, or "Calm would like to
/// access files in your Documents folder" when a shell first lists it. macOS keeps each answer;
/// Calm asks once and never again.
@MainActor
enum FirstLaunchPermissions {
    private static let asked = "askedForPermissions"

    /// The folders macOS guards, which a shell started by Calm reaches as Calm. Reading one is
    /// what makes macOS ask; there is no call to ask in advance.
    private nonisolated static let guardedFolders: [FileManager.SearchPathDirectory] = [
        .documentDirectory,
        .desktopDirectory,
        .downloadsDirectory,
    ]

    static func askOnce() {
        // Tests and self-tests never show the user a prompt (`AttentionCenter.deliversNotifications`).
        guard AttentionCenter.deliversNotifications, !Headless.isOn,
              !UserDefaults.standard.bool(forKey: asked)
        else { return }
        UserDefaults.standard.set(true, forKey: asked)
        Task {
            // One prompt at a time: the next waits for the answer to the one before.
            _ = await AttentionCenter.shared.requestAuthorization().value
            await Task.detached(priority: .utility) {
                for directory in guardedFolders {
                    guard let url = FileManager.default.urls(for: directory, in: .userDomainMask).first else { continue }
                    _ = try? FileManager.default.contentsOfDirectory(atPath: url.path)
                }
            }.value
        }
    }
}
