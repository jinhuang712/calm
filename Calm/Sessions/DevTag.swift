import SwiftUI

/// The dev build's mark of itself (BuildVariant): plain small capitals in the icon's violet, on the
/// line of the strip above the sidebar's search field, where the section headers' type already
/// lives. No box, and nothing else in the chrome takes the color (UIUX.md → The dev build).
struct DevTag: View {
    let isDark: Bool

    var body: some View {
        Text("DEV")
            .calmFont(size: 11, weight: .semibold)
            .tracking(1)
            .foregroundStyle(isDark ? Color(red: 0.72, green: 0.66, blue: 0.91) : Color(red: 0.49, green: 0.37, blue: 0.83))
            .padding(.trailing, 20.scaled)
            .accessibilityLabel("Development build")
    }
}
