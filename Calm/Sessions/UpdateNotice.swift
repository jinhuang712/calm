import CalmModel
import SwiftUI

/// The sidebar strip's notice that a newer Calm is out (UIUX.md → The sidebar): `↑ 0.2.0` in quiet
/// text, on the line beside the traffic lights where the dev build's tag sits. No box, and not
/// amber, which is *needs you*: an update never does. A click opens a small menu.
struct UpdateNotice: View {
    let release: CalmRelease
    let style: SidebarStyle
    @State private var hovered = false

    var body: some View {
        Menu {
            Button("Release Notes") { UpdateChecker.openReleasePage(release) }
            Button("Copy Update Command") { UpdateChecker.copyUpdateCommand() }
            Divider()
            Button("Skip \(release.version.description)") { UpdateChecker.shared.skip(release) }
        } label: {
            HStack(spacing: 4.scaled) {
                Image(systemName: "arrow.up")
                    .calmFont(size: 9.5, weight: .bold)
                Text(release.version.description)
                    .calmFont(size: 12, weight: .medium)
            }
            .foregroundStyle(hovered ? style.primary : style.secondary)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovered = $0 }
        .help("Calm \(release.version.description) is out")
        .accessibilityLabel("Calm \(release.version.description) is out")
    }
}

/// Calm → Check for Updates…: the one place Calm answers in words, since you asked.
@MainActor
enum UpdateAlert {
    static func checkByHand() {
        Task {
            await show(UpdateChecker.shared.check(byHand: true))
        }
    }

    static func show(_ outcome: UpdateChecker.Outcome) {
        let running = UpdateChecker.bundleVersion?.description ?? "?"
        let alert = NSAlert()
        switch outcome {
        case let .offer(release):
            alert.messageText = "Calm \(release.version.description) is out"
            alert.informativeText = "You have \(running)."
            alert.addButton(withTitle: "Release Notes")
            alert.addButton(withTitle: "Copy Update Command")
            alert.addButton(withTitle: "Not Now")
            switch alert.runModal() {
            case .alertFirstButtonReturn: UpdateChecker.openReleasePage(release)
            case .alertSecondButtonReturn: UpdateChecker.copyUpdateCommand()
            default: break
            }
            return
        case .upToDate:
            alert.messageText = "\(BuildVariant.appName) is up to date"
            alert.informativeText = "\(running) is the newest release."
        case let .failed(reason):
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = reason
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
