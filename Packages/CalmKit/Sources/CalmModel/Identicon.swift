/// A project's pixel mark, made from its name the way GitHub and GitLab make identicons: a 5×5
/// grid mirrored left to right, so the same name always gets the same mark, on every Mac and
/// launch. Shape only: the sidebar draws it in the theme's own color, which stays for state.
public struct Identicon: Equatable, Sendable {
    public static let size = 5

    /// Rows top to bottom; `true` is a filled cell.
    public let cells: [[Bool]]

    public init(name: String) {
        // Of the 15 bits a mark takes, too few read as noise and too many as a block: mix again
        // until the count sits in between (a few rounds at most, and always the same ones).
        var hash = Self.mix(Self.fnv1a(name.lowercased()))
        while !(5 ... 11).contains((hash & 0x7FFF).nonzeroBitCount) {
            hash = Self.mix(hash)
        }
        // The bits fill the left three columns; the right two mirror them.
        var cells = [[Bool]](repeating: [Bool](repeating: false, count: Self.size), count: Self.size)
        for row in 0 ..< Self.size {
            for column in 0 ..< 3 {
                let isOn = hash >> UInt64(row * 3 + column) & 1 == 1
                cells[row][column] = isOn
                cells[row][Self.size - 1 - column] = isOn
            }
        }
        self.cells = cells
    }

    /// Not `Hasher`: it's seeded per process, and a mark must not change between launches.
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// splitmix64's finalizer, so names that differ by a letter still look apart.
    static func mix(_ value: UInt64) -> UInt64 {
        var hash = value &+ 0x9E37_79B9_7F4A_7C15
        hash = (hash ^ hash >> 30) &* 0xBF58_476D_1CE4_E5B9
        hash = (hash ^ hash >> 27) &* 0x94D0_49BB_1331_11EB
        return hash ^ hash >> 31
    }
}
