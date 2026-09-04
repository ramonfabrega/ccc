import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CCCKit

/// The colour oracle (v8 slice 3, queue item 10): reading a colour back out
/// of a captured image, and turning a grid cell into the pixel to read.
///
/// These build their own PNGs rather than shipping a fixture: the question
/// is whether a known colour survives the round trip, and a colour written
/// here is known in a way a recorded file never quite is.
@Suite struct PixelTests {
    /// A PNG with one colour per quadrant, so a wrong y-flip or a swapped
    /// channel cannot pass — the failure modes this decoder actually has.
    private func quadrants(width: Int = 40, height: Int = 20) throws -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // CGContext's origin is bottom-left; these names are what the
        // *image* shows, which is what `rgb(x:y:)` indexes.
        let cells: [(CGRect, CGColor)] = [
            (CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2),      // top-left
             CGColor(srgbRed: 21 / 255, green: 25 / 255, blue: 31 / 255, alpha: 1)),  // #15191F
            (CGRect(x: width / 2, y: height / 2, width: width / 2, height: height / 2),
             CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)),                       // #FF0000
            (CGRect(x: 0, y: 0, width: width / 2, height: height / 2),                // bottom-left
             CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)),                       // #00FF00
            (CGRect(x: width / 2, y: 0, width: width / 2, height: height / 2),
             CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)),                       // #0000FF
        ]
        for (rect, color) in cells {
            context.setFillColor(color)
            context.fill(rect)
        }
        let image = context.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return out as Data
    }

    @Test func aColourSurvivesTheRoundTrip() throws {
        let image = try PixelReader.decode(quadrants())
        #expect(image.width == 40)
        #expect(image.height == 20)
        #expect(image.rgb(x: 5, y: 5) == Frame.RGB(0x15, 0x19, 0x1F))
        #expect(PixelReader.hex(image.rgb(x: 5, y: 5)!) == "#15191F")
    }

    /// The y-flip is the bug this decoder is most likely to have: AppKit
    /// measures up from the bottom, an image is indexed down from the top.
    @Test func theOriginIsTheImagesTopLeft() throws {
        let image = try PixelReader.decode(quadrants())
        #expect(image.rgb(x: 30, y: 5) == Frame.RGB(0xFF, 0, 0))     // top-right
        #expect(image.rgb(x: 5, y: 15) == Frame.RGB(0, 0xFF, 0))     // bottom-left
        #expect(image.rgb(x: 30, y: 15) == Frame.RGB(0, 0, 0xFF))    // bottom-right
    }

    /// Off the edge is nil, never a clamped colour: asking for a pixel that
    /// is not there is a mistake worth hearing about.
    @Test func outsideTheImageIsNothing() throws {
        let image = try PixelReader.decode(quadrants())
        #expect(image.rgb(x: 40, y: 0) == nil)
        #expect(image.rgb(x: 0, y: 20) == nil)
        #expect(image.rgb(x: -1, y: 0) == nil)
    }

    @Test func somethingThatIsNotAnImageSaysSo() {
        #expect(throws: PixelReader.Failure.self) {
            _ = try PixelReader.decode(Data("not a png".utf8))
        }
    }

    @Test func hexParsesBothSpellingsAndRefusesTherest() {
        #expect(PixelReader.parse(hex: "#15191F") == Frame.RGB(0x15, 0x19, 0x1F))
        #expect(PixelReader.parse(hex: "15191f") == Frame.RGB(0x15, 0x19, 0x1F))
        // A colour that does not parse must not become black by accident.
        for bad in ["", "#15191", "#15191FF", "zzzzzz", "#ggg000"] {
            #expect(PixelReader.parse(hex: bad) == nil, "\(bad)")
        }
    }

    /// Distance is the largest single-channel difference, so the number
    /// names the channel and the amount.
    @Test func distanceIsTheWorstChannel() {
        let a = Frame.RGB(21, 25, 31)
        #expect(PixelReader.distance(a, a) == 0)
        #expect(PixelReader.distance(a, Frame.RGB(21, 25, 40)) == 9)
        #expect(PixelReader.distance(a, Frame.RGB(30, 25, 33)) == 9)
    }

    // MARK: aiming at a cell

    private let pane = WindowGeometry.Pane(
        x: 429, y: 38, width: 843, height: 755,
        cols: 93, rows: 47, cellWidth: 9, cellHeight: 16)

    /// The centre of the cell, not a corner: a corner sits on the boundary
    /// between two cells and on the edge of a glyph's antialiasing, where
    /// "what colour is this" is legitimately ambiguous.
    @Test func aCellBecomesThePixelAtItsCentre() {
        let (x, y) = pane.pixel(col: 0, row: 0, scale: 1)
        #expect((x, y) == (429 + 4, 38 + 8))
        let (x2, y2) = pane.pixel(col: 10, row: 3, scale: 1)
        #expect((x2, y2) == (429 + 94, 38 + 56))
    }

    /// Points in, pixels out: the geometry never changes when the window
    /// moves to a Retina display, only the scale does.
    @Test func scaleTurnsPointsIntoPixels() {
        let (x, y) = pane.pixel(col: 0, row: 0, scale: 2)
        #expect((x, y) == ((429 + 4) * 2 + 1, (38 + 8) * 2))
    }

    /// The wire carries the new answer, and an older `ccc` on the far side
    /// of a hop is not what this protects — a request it has never heard of
    /// is an error, not a decode failure.
    @Test func geometryCrossesTheWire() throws {
        let sent = WindowGeometry(windowID: 8864, scale: 1, x: 120, y: 64, width: 1280, height: 800, pane: pane)
        let data = try JSONEncoder().encode(ControlResponse.geometry(sent))
        guard case .geometry(let back) = try JSONDecoder().decode(ControlResponse.self, from: data) else {
            Issue.record("not a geometry response")
            return
        }
        #expect(back == sent)
        #expect(back.pane?.cols == 93)
        // Where the window sits crosses too: it is what says a restored
        // frame is the frame that was saved.
        #expect((back.x, back.y) == (120, 64))
        let request = try JSONEncoder().encode(ControlRequest.geometry)
        #expect(String(decoding: request, as: UTF8.self).contains("geometry"))
    }

    /// A window with nothing attached still answers — the id is what
    /// `screencapture -l` needs, and it exists whether or not a pane does.
    @Test func aWindowWithNoPaneStillHasAnId() throws {
        let sent = WindowGeometry(windowID: 12, scale: 2, x: 0, y: 0, width: 100, height: 50)
        let data = try JSONEncoder().encode(ControlResponse.geometry(sent))
        guard case .geometry(let back) = try JSONDecoder().decode(ControlResponse.self, from: data) else {
            Issue.record("not a geometry response")
            return
        }
        #expect(back.pane == nil)
        #expect(back.windowID == 12)
    }
}
