public extension PiAdapter {
    /// pi's pixel π: a coral bar over a blue and a gold leg.
    /// Source: pi.dev/logo-auto.svg; the mark is pi's.
    var mark: AgentMarkArt {
        AgentMarkArt(
            viewBox: .init(x: 150, y: 150, side: 500),
            shapes: [
                .init(
                    "M165.29 282.65H282.65V400H400V517.36H282.65V634.72H165.29Z",
                    fill: .color("#4D9ABF"),
                ),
                .init(
                    "M165.29 165.29H517.36V400H400V282.65H165.29Z",
                    fill: .color("#F09082"),
                ),
                .init(
                    "M517.36 400H634.72V634.72H517.36Z",
                    fill: .color("#F1BE58"),
                ),
            ],
            motion: .build,
            scale: 0.62,
        )
    }
}
