import AppKit
import Foundation
import Security

/// The first launch of each build asks for everything Calm will need, one prompt after another,
/// so none arrives in the middle of work: a notification when an agent needs you, or "Calm would
/// like to access files in your Documents folder" when a shell first lists it. macOS keeps each
/// answer for that build only. Calm is signed ad hoc, so every new build has a new code hash and
/// macOS forgets what the old one was allowed. Calm asks again once per build, never twice.
@MainActor
enum FirstLaunchPermissions {
    /// The build that was last asked. Replaces the old `askedForPermissions` flag, which was set
    /// once and so never asked again after an update.
    private static let askedBuild = "askedForPermissionsBuild"

    /// The folders macOS guards, which a shell started by Calm reaches as Calm. Reading one is
    /// what makes macOS ask; there is no call to ask in advance.
    private nonisolated static let guardedFolders: [FileManager.SearchPathDirectory] = [
        .documentDirectory,
        .desktopDirectory,
        .downloadsDirectory,
    ]

    /// Whether this build still has to ask. A user from before this existed has no saved build,
    /// so the first launch after the update asks once more, which is what an update needs anyway.
    nonisolated static func shouldAsk(saved: String?, current: String) -> Bool {
        saved != current
    }

    /// What macOS tells builds apart by: the hash of the code signature. Another build of the
    /// same version has another hash, so the version alone is not enough. Falls back to the
    /// version when the signature cannot be read, which asks at most once per version.
    nonisolated static func buildIdentity(bundle: Bundle = .main) -> String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code,
           SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
           SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
           let unique = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data {
            return unique.map { String(format: "%02x", $0) }.joined()
        }
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static func askOnce() {
        // Tests and self-tests never show the user a prompt (`AttentionCenter.deliversNotifications`).
        guard AttentionCenter.deliversNotifications, !Headless.isOn else { return }
        let current = buildIdentity()
        guard shouldAsk(saved: UserDefaults.standard.string(forKey: askedBuild), current: current) else { return }
        UserDefaults.standard.set(current, forKey: askedBuild)
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
