import Foundation

/// What the renderer draws: one viewport's worth of rows, already resolved
/// (colors flattened, wide cells marked, dirty rows flagged). Built by
/// `FrameReader` from libghostty-vt's render state; consumed by the Metal
/// renderer. Plain values so the reader and the renderer can be developed
/// and tested apart, and so a frame can be dumped as JSON for a bug report.
public struct Frame: Sendable, Equatable {
    public var cols: Int
    public var rows: [Row]
    public var cursor: Cursor?
    public var background: RGB
    public var foreground: RGB
    /// `full` when every row must redraw (resize, palette change, first
    /// frame); otherwise only rows with `dirty == true` changed since the
    /// last frame the reader produced.
    public var dirty: Dirty

    public enum Dirty: Sendable, Equatable { case none, partial, full }

    public struct Row: Sendable, Equatable {
        public var y: Int
        public var dirty: Bool
        public var cells: [Cell]
        /// Selected column range in this row, if any.
        public var selection: Range<Int>?
    }

    public struct Cell: Sendable, Equatable {
        /// The grapheme cluster as text; empty for a blank cell or a wide
        /// spacer tail.
        public var text: String
        public var wide: Wide
        /// Resolved colors, nil = use the frame default.
        public var fg: RGB?
        public var bg: RGB?
        public var flags: Flags
        public var underline: Underline
        public var underlineColor: RGB?

        public enum Wide: UInt8, Sendable { case narrow, wide, spacerTail, spacerHead }
        public enum Underline: UInt8, Sendable { case none, single, double, curly, dotted, dashed }

        public struct Flags: OptionSet, Sendable, Equatable {
            public let rawValue: UInt16
            public init(rawValue: UInt16) { self.rawValue = rawValue }
            public static let bold = Flags(rawValue: 1 << 0)
            public static let italic = Flags(rawValue: 1 << 1)
            public static let faint = Flags(rawValue: 1 << 2)
            public static let blink = Flags(rawValue: 1 << 3)
            public static let inverse = Flags(rawValue: 1 << 4)
            public static let invisible = Flags(rawValue: 1 << 5)
            public static let strikethrough = Flags(rawValue: 1 << 6)
            public static let overline = Flags(rawValue: 1 << 7)
        }

        public static let blank = Cell(text: "", wide: .narrow, fg: nil, bg: nil, flags: [], underline: .none, underlineColor: nil)
    }

    public struct Cursor: Sendable, Equatable {
        public var x: Int
        public var y: Int
        public var style: Style
        public var visible: Bool
        public var blinking: Bool
        public var wideTail: Bool
        public var color: RGB?
        public enum Style: UInt8, Sendable { case block, blockHollow, bar, underline }
    }

    public struct RGB: Sendable, Equatable, Hashable {
        public var r: UInt8, g: UInt8, b: UInt8
        public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
    }
}
