import SwiftUI

/// Reads SVG path data (the `d` attribute) into a SwiftUI path, for agent marks: moves, lines,
/// cubic and quadratic curves and closes, absolute or relative. Anything else (arcs, bad
/// numbers) returns nil, and the mark falls back to the agent's letter (degrade, don't crash).
enum SVGPath {
    enum Command: Equatable {
        case move(CGPoint)
        case line(CGPoint)
        case cubic(CGPoint, CGPoint, to: CGPoint)
        case quad(CGPoint, to: CGPoint)
        case close
    }

    static func path(_ data: String) -> Path? {
        guard let commands = commands(data) else { return nil }
        var path = Path()
        for command in commands {
            switch command {
            case let .move(point): path.move(to: point)
            case let .line(point): path.addLine(to: point)
            case let .cubic(control1, control2, end): path.addCurve(to: end, control1: control1, control2: control2)
            case let .quad(control, end): path.addQuadCurve(to: end, control: control)
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    /// The path as absolute commands: relative forms, H/V and the smooth S/T resolved.
    static func commands(_ data: String) -> [Command]? {
        guard let tokens = tokens(data) else { return nil }
        var reader = Reader(tokens: tokens)
        return reader.read()
    }

    private enum Token: Equatable {
        case letter(Character)
        case number(Double)
    }

    /// Splits "m4.7.079-.23L6 9Z" into letters and numbers; SVG lets numbers run together.
    private static func tokens(_ data: String) -> [Token]? {
        var tokens: [Token] = []
        let characters = Array(data)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace || character == "," {
                index += 1
            } else if character.isLetter, character != "e", character != "E" {
                tokens.append(.letter(character))
                index += 1
            } else {
                let start = index
                if characters[index] == "-" || characters[index] == "+" {
                    index += 1
                }
                var seenDot = false
                while index < characters.count {
                    let next = characters[index]
                    if next.isNumber {
                        index += 1
                    } else if next == ".", !seenDot {
                        seenDot = true
                        index += 1
                    } else if next == "e" || next == "E" {
                        index += 1
                        if index < characters.count, characters[index] == "-" || characters[index] == "+" {
                            index += 1
                        }
                    } else {
                        break
                    }
                }
                guard index > start, let value = Double(String(characters[start ..< index])) else { return nil }
                tokens.append(.number(value))
            }
        }
        return tokens
    }

    private struct Reader {
        let tokens: [Token]
        var index = 0
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        /// The last curve's second control point, reflected by S and T.
        var lastControl: CGPoint?

        init(tokens: [Token]) {
            self.tokens = tokens
        }

        mutating func read() -> [Command]? {
            var commands: [Command] = []
            var letter: Character?
            while index < tokens.count {
                if case let .letter(next) = tokens[index] {
                    letter = next
                    index += 1
                } else if letter == nil {
                    return nil
                }
                guard let command = letter else { return nil }
                guard let produced = step(command) else { return nil }
                commands.append(contentsOf: produced)
                // After a move, further pairs are lines (SVG's implicit command).
                if command == "M" {
                    letter = "L"
                } else if command == "m" {
                    letter = "l"
                }
                if command == "Z" || command == "z" {
                    letter = nil
                }
            }
            return commands
        }

        private mutating func numbers(_ count: Int) -> [Double]? {
            guard index + count <= tokens.count else { return nil }
            var values: [Double] = []
            for token in tokens[index ..< index + count] {
                guard case let .number(value) = token else { return nil }
                values.append(value)
            }
            index += count
            return values
        }

        private func point(_ x: Double, _ y: Double, relative: Bool) -> CGPoint {
            relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        private mutating func step(_ letter: Character) -> [Command]? {
            let relative = letter.isLowercase
            switch letter.uppercased() {
            case "Z":
                current = subpathStart
                lastControl = nil
                return [.close]
            case "M":
                guard let v = numbers(2) else { return nil }
                current = point(v[0], v[1], relative: relative)
                subpathStart = current
                lastControl = nil
                return [.move(current)]
            case "L":
                guard let v = numbers(2) else { return nil }
                return line(to: point(v[0], v[1], relative: relative))
            case "H":
                guard let v = numbers(1) else { return nil }
                return line(to: CGPoint(x: relative ? current.x + v[0] : v[0], y: current.y))
            case "V":
                guard let v = numbers(1) else { return nil }
                return line(to: CGPoint(x: current.x, y: relative ? current.y + v[0] : v[0]))
            case "C":
                guard let v = numbers(6) else { return nil }
                return cubic(
                    point(v[0], v[1], relative: relative), point(v[2], v[3], relative: relative), point(v[4], v[5], relative: relative),
                )
            case "S":
                guard let v = numbers(4) else { return nil }
                return cubic(reflected, point(v[0], v[1], relative: relative), point(v[2], v[3], relative: relative))
            case "Q":
                guard let v = numbers(4) else { return nil }
                return quad(point(v[0], v[1], relative: relative), point(v[2], v[3], relative: relative))
            case "T":
                guard let v = numbers(2) else { return nil }
                return quad(reflected, point(v[0], v[1], relative: relative))
            default:
                return nil
            }
        }

        private var reflected: CGPoint {
            guard let lastControl else { return current }
            return CGPoint(x: 2 * current.x - lastControl.x, y: 2 * current.y - lastControl.y)
        }

        private mutating func line(to end: CGPoint) -> [Command] {
            current = end
            lastControl = nil
            return [.line(end)]
        }

        private mutating func cubic(_ control1: CGPoint, _ control2: CGPoint, _ end: CGPoint) -> [Command] {
            current = end
            lastControl = control2
            return [.cubic(control1, control2, to: end)]
        }

        private mutating func quad(_ control: CGPoint, _ end: CGPoint) -> [Command] {
            current = end
            lastControl = control
            return [.quad(control, to: end)]
        }
    }
}
