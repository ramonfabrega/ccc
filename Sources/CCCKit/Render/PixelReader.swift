import CoreGraphics
import Foundation
import ImageIO

/// Reading a colour back out of a captured image.
///
/// The other half of CLAUDE.md's "the human's screen is the oracle for
/// presentation". `ccc peek` composites the pane from an offscreen render,
/// so it can show a perfect TUI over a pane that is black on screen — it
/// did, for a day (docs/DESIGN.md §7). A real `screencapture` answers that,
/// but only if something can then *read* it: until this, nothing in the
/// repo could turn a PNG into a number, so every colour question ended in
/// a human looking at a picture. `Grid` carries no colour (`GridBuilder`
/// never had one), so the text oracle cannot answer it either.
///
/// Deliberately not a general image library: one function, one pixel, no
/// resizing, no colour conversion beyond what CoreGraphics does to put the
/// bytes in a known order. Anything cleverer would need a reason.
public enum PixelReader {
    public struct Image: Sendable {
        /// Pixels, not points: what a caller indexes.
        public let width: Int
        public let height: Int
        private let pixels: [UInt8]        // RGBA, row-major, premultiplied-last

        init(width: Int, height: Int, pixels: [UInt8]) {
            self.width = width
            self.height = height
            self.pixels = pixels
        }

        /// The colour at a pixel, with the origin at the **top-left** —
        /// the way an image is indexed and a screenshot is read, not the
        /// bottom-left of AppKit's coordinate space. Out of bounds is nil
        /// rather than a clamp: asking for a pixel that is not there is a
        /// mistake worth hearing about, not a colour worth guessing.
        public func rgb(x: Int, y: Int) -> Frame.RGB? {
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            let i = (y * width + x) * 4
            return Frame.RGB(pixels[i], pixels[i + 1], pixels[i + 2])
        }
    }

    public enum Failure: Error, CustomStringConvertible {
        case notAnImage
        case cannotDecode
        public var description: String {
            switch self {
            case .notAnImage: return "not an image ccc can read"
            case .cannotDecode: return "the image could not be decoded"
            }
        }
    }

    /// Decode PNG (or anything ImageIO reads) into straight RGBA bytes.
    ///
    /// The redraw into our own context is the point: a captured PNG can
    /// carry any bit depth, byte order or colour profile, and reading its
    /// raw data would make the answer depend on which. Drawing it into a
    /// known 8-bit RGBA sRGB context makes "what colour is this pixel" a
    /// question with one answer.
    public static func decode(_ data: Data) throws -> Image {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure.notAnImage
        }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw Failure.cannotDecode }
        let ok: Bool = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { throw Failure.cannotDecode }
        return Image(width: width, height: height, pixels: pixels)
    }

    /// How far apart two colours are, as the largest single-channel
    /// difference. Chosen over a Euclidean distance because the number it
    /// prints is the one a reader can act on: "blue is 9 off" names the
    /// channel and the amount, and a tolerance in those units is a
    /// sentence ("within 2 of the theme") rather than a radius.
    public static func distance(_ a: Frame.RGB, _ b: Frame.RGB) -> Int {
        max(abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b)))
    }

    /// `#RRGGBB`, or `RRGGBB`. Nil for anything else — a colour that does
    /// not parse must not become black by accident.
    public static func parse(hex: String) -> Frame.RGB? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return Frame.RGB(UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF))
    }

    /// `#RRGGBB` — the spelling `ccc theme` prints, so the two verbs'
    /// output can be compared by eye as well as by exit code.
    public static func hex(_ c: Frame.RGB) -> String {
        String(format: "#%02X%02X%02X", c.r, c.g, c.b)
    }
}
