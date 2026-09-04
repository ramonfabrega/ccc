import Foundation
import Testing
@testable import CCCKit

/// The window's gestures, as the socket carries them. The rule this suite
/// exists for is CLAUDE.md's: *what can be clicked can be scripted and the
/// reverse.* The click side lives in AppKit and cannot be asserted here —
/// what can is that the grammar the CLI parses, the string the socket
/// carries and the switch the window answers with are **one definition**,
/// which is why `WindowAction` is a type rather than three string lists.
@Suite struct WindowActionTests {
    /// Every gesture the title bar has, named. The list is written out
    /// rather than read from `grammar` on purpose: this is the assertion
    /// that a gesture was not quietly dropped, and reading the grammar to
    /// check the grammar would assert nothing.
    @Test func everyTitleBarGestureHasAVerb() {
        let expected = ["show", "hide", "close", "minimize", "zoom", "fullscreen", "center",
                        "move", "resize", "frame", "split", "add-host", "new-session"]
        #expect(WindowAction.grammar.map(\.verb) == expected)
        for verb in expected {
            #expect(WindowAction.usage.contains(verb), "\(verb) is missing from what the CLI and the socket print")
        }
    }

    /// The wire is a string and the app parses it back: what the CLI sends
    /// has to be what the window reads, or a gesture works from one face
    /// and not the other.
    @Test func everyActionRoundTrips() {
        let actions: [WindowAction] = [
            .show, .hide, .close, .minimize, .zoom, .fullScreen, .center, .addHost, .newSession,
            .move(x: 120, y: 64), .resize(width: 1280, height: 800),
            .frame(x: 0, y: 25, width: 1440, height: 900), .split(width: 420),
        ]
        for action in actions {
            #expect(WindowAction(action.text) == action, "\(action.text) did not survive the wire")
        }
    }

    /// Whole points print whole: `move 120 64` is what a person would type,
    /// and what `ccc geometry` prints back at them.
    @Test func numbersPrintTheWayGeometryDoes() {
        #expect(WindowAction.move(x: 120, y: 64).text == "move 120 64")
        #expect(WindowAction.frame(x: 0, y: 25, width: 1440, height: 900).text == "frame 0 25 1440 900")
    }

    /// A missing argument is a typo, not a shorter gesture: `move 100` must
    /// not silently become anything.
    @Test func aVerbMustCarryItsOwnNumbers() {
        #expect(WindowAction("move 100") == nil)
        #expect(WindowAction("move 100 200 300") == nil)
        #expect(WindowAction("resize") == nil)
        #expect(WindowAction("frame 1 2 3") == nil)
        #expect(WindowAction("split") == nil)
        #expect(WindowAction("show 100") == nil)
        #expect(WindowAction("move left down") == nil)
        #expect(WindowAction("maximise") == nil)
        #expect(WindowAction("") == nil)
    }

    /// Fractional points survive — a window can land on a half point on a
    /// Retina display, and a geometry read has to be pasteable back.
    @Test func aHalfPointIsAPoint() {
        #expect(WindowAction("move 120.5 64") == .move(x: 120.5, y: 64))
        #expect(WindowAction.move(x: 120.5, y: 64).text == "move 120.5 64")
    }
}
