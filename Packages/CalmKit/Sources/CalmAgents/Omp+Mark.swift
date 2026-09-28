public extension OmpAdapter {
    /// omp's block π in its pink, violet and cyan gradient.
    /// Source: omp.sh/favicon.svg; the mark is omp's.
    var mark: AgentMarkArt {
        AgentMarkArt(
            viewBox: .init(x: 12, y: 16, side: 40),
            shapes: [
                .init(
                    "M14 16h36v8H40v32h-8V24h-6v22h-8V24h-4z",
                    fill: .gradient(["#ED4ABF", "#9B4DFF", "#5AD8E6"]),
                ),
            ],
            motion: .gradientTurn,
            scale: 0.66,
        )
    }
}
