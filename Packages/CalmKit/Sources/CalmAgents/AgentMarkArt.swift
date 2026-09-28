/// An agent's own mark and the way it moves while the agent works (UIUX.md → Agent marks).
/// Data only: shapes as SVG path data, colors as hex. The sidebar draws and animates any mark
/// the same way, so a new agent brings its art here and the core never special-cases it.
///
/// The marks are the agents' own logos and belong to their owners (see NOTICE); Calm shows them
/// only to say which agent a session runs.
public struct AgentMarkArt: Sendable, Equatable {
    public struct Shape: Sendable, Equatable {
        /// SVG path data, in the mark's `viewBox`.
        public var path: String
        public var fill: Fill
        /// SVG's `fill-rule="evenodd"`: holes cut by overlapping subpaths.
        public var evenOdd: Bool

        public init(_ path: String, fill: Fill, evenOdd: Bool = false) {
            self.path = path
            self.fill = fill
            self.evenOdd = evenOdd
        }
    }

    public enum Fill: Sendable, Equatable {
        /// `#RRGGBB` on a dark and on a light background.
        case color(dark: String, light: String)
        /// Colors from the top-left corner to the bottom-right one.
        case gradient([String])

        public static func color(_ hex: String) -> Fill {
            .color(dark: hex, light: hex)
        }
    }

    /// How the mark moves while its agent works, and how it settles when the work ends.
    public enum Motion: Sendable, Equatable {
        /// Turns, gathers into a dot, and blooms back.
        case bloom
        /// One eased full turn, then a short rest.
        case turnAndRest
        /// Twelve small squares pulsing on their own rhythms, in place of the mark.
        case pulseGrid
        /// The shapes drop into place one by one, hold, and fall away.
        case build
        /// The gradient turns inside the mark while a shine crosses it.
        case gradientTurn
    }

    /// The square the paths are drawn in.
    public struct ViewBox: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var side: Double

        public init(x: Double, y: Double, side: Double) {
            self.x = x
            self.y = y
            self.side = side
        }
    }

    public var viewBox: ViewBox
    public var shapes: [Shape]
    public var motion: Motion
    /// How much of its tile the mark fills, 0…1: marks differ in how much of their box they use.
    public var scale: Double

    public init(viewBox: ViewBox, shapes: [Shape], motion: Motion, scale: Double) {
        self.viewBox = viewBox
        self.shapes = shapes
        self.motion = motion
        self.scale = scale
    }
}
