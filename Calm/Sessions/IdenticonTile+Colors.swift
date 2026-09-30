import CalmModel
import SwiftUI

extension IdenticonTile {
    /// The mark's two colors: its pixels (`ink`) and the pale tile under them. Search's count of a
    /// project's past sessions wears them too.
    static func colors(of identicon: Identicon, style: SidebarStyle) -> (ink: Color, tile: Color) {
        let hue = identicon.hue
        return (
            Color(hue: hue, saturation: style.isDark ? 0.38 : 0.42, brightness: style.isDark ? 0.78 : 0.62),
            Color(hue: hue, saturation: 0.18, brightness: style.isDark ? 0.26 : 0.93),
        )
    }
}
