import CalmModel
import SwiftUI

/// Settings → Appearance → Interface size (UIUX.md → Accessibility): one factor for every size
/// and length in Calm's chrome (the sidebar, cards, Settings, search, panels), never the terminal.
/// Views read it through `.calmFont` and `.scaled`; it's observable, so a change redraws them.
@MainActor
@Observable
final class InterfaceScale {
    static let shared = InterfaceScale()

    private(set) var factor: CGFloat = 1

    private init() {
        factor = CGFloat(SessionManager.shared.settings.interfaceSize.scale)
    }

    /// Follows config.toml (called whenever the settings are read or saved).
    func update(from settings: CalmSettings) {
        let factor = CGFloat(settings.interfaceSize.scale)
        if factor != self.factor {
            self.factor = factor
        }
    }
}

extension CGFloat {
    /// This length at the interface size (UIUX.md → Accessibility).
    @MainActor
    var scaled: CGFloat {
        self * InterfaceScale.shared.factor
    }
}

extension Double {
    @MainActor
    var scaled: CGFloat {
        CGFloat(self) * InterfaceScale.shared.factor
    }
}

extension Int {
    @MainActor
    var scaled: CGFloat {
        CGFloat(self) * InterfaceScale.shared.factor
    }
}

private struct CalmFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight?
    let design: Font.Design?

    func body(content: Content) -> some View {
        // Read here, so the view redraws when the interface size changes.
        content.font(.system(size: size * InterfaceScale.shared.factor, weight: weight, design: design))
    }
}

extension View {
    /// The system font at `size` points of the standard interface size, grown with it.
    func calmFont(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        modifier(CalmFont(size: size, weight: weight, design: design))
    }
}
