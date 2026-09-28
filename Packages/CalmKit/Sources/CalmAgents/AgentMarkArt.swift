import Foundation

/// An agent's own mark and the way it moves while the agent works (UIUX.md → Agent marks).
/// Data only: shapes as SVG path data, colors as hex, and for some an animation's frames. The sidebar draws and animates any mark
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
        /// The agent's own animation, `frames`, looping in place of the mark; the mark fades
        /// back in when the work ends.
        case frames
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

    /// An animation played as it is, frame by frame, for marks whose own motion is hard to
    /// pose from their shapes.
    public struct Frames: Sendable, Equatable {
        /// Square images with transparent backgrounds, all the same size.
        public var images: [URL]
        /// Which image shows in each frame, in order, as indices into `images`; it loops.
        public var sequence: [Int]
        public var framesPerSecond: Double
        /// How much of its tile an image fills, 0…1, as `scale` is for the mark.
        public var scale: Double

        public init(images: [URL], sequence: [Int], framesPerSecond: Double, scale: Double) {
            self.images = images
            self.sequence = sequence
            self.framesPerSecond = framesPerSecond
            self.scale = scale
        }
    }

    public var viewBox: ViewBox
    public var shapes: [Shape]
    public var motion: Motion
    /// How much of its tile the mark fills, 0…1: marks differ in how much of their box they use.
    public var scale: Double
    /// For `.frames`; nil when the images can't be found, and the mark then stays still.
    public var frames: Frames?

    public init(viewBox: ViewBox, shapes: [Shape], motion: Motion, scale: Double, frames: Frames? = nil) {
        self.viewBox = viewBox
        self.shapes = shapes
        self.motion = motion
        self.scale = scale
        self.frames = frames
    }
}
