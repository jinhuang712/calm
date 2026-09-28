public extension OpenCodeAdapter {
    /// OpenCode's block frame with its filled square.
    /// Source: anomalyco/opencode, packages/identity/mark.svg (MIT); the mark is OpenCode's.
    var mark: AgentMarkArt {
        AgentMarkArt(
            viewBox: .init(x: 64, y: 64, side: 384),
            shapes: [
                .init(
                    "M320 224V352H192V224H320Z",
                    fill: .color(dark: "#5A5858", light: "#C9C7C7"),
                ),
                .init(
                    "M384 416H128V96H384V416ZM320 160H192V352H320V160Z",
                    fill: .color(dark: "#FFFFFF", light: "#17181C"), evenOdd: true,
                ),
            ],
            motion: .pulseGrid,
            scale: 0.62,
        )
    }
}
