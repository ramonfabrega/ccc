import Foundation
import Testing

@testable import CCCKit

/// DEC 1004 focus reporting (item 17 slice 2), driven through the real core.
///
/// This is the one seam member whose effect is invisible on this Mac: the
/// harness enables mode 1004 on every session it runs (measured 2026-09-04,
/// `decModes` in the daemon's roster: 1004 on 8 of 8 workers), pulses "the
/// user is at this terminal" to Anthropic while focus is reported, and
/// **suppresses the phone's push while that is true**. Its guard skips the
/// pulse only on an explicit blur, so a terminal that reports nothing is
/// treated as present forever — which is what ccc did until this file
/// existed. The assertions below are therefore about bytes, because bytes
/// are the only place the behaviour is observable without a phone.
@Suite struct FocusReportTests {
    /// `CSI I` and `CSI O` — the whole protocol.
    static let focusIn = Data([0x1b, 0x5b, 0x49])
    static let focusOut = Data([0x1b, 0x5b, 0x4f])

    /// A host with a sink on its output, and the child's mode 1004 already
    /// enabled if asked — `CSI ? 1004 h` is what a real TUI sends.
    @MainActor private func host(focusMode: Bool) -> (GhosttyHost, () -> Data) {
        let host = GhosttyHost(cols: 20, rows: 4)
        let box = Box()
        host.onOutput = { box.data.append($0) }
        if focusMode { host.feed(Data("\u{1b}[?1004h".utf8)) }
        box.data = Data()   // the mode-enable may itself provoke a reply
        return (host, { box.data })
    }

    private final class Box: @unchecked Sendable { var data = Data() }

    /// The child asked for focus events, so it gets them, in both
    /// directions and in the right spelling.
    @MainActor @Test func aListeningChildIsToldBothWays() {
        let (host, output) = host(focusMode: true)
        #expect(host.setFocused(true) == true)
        #expect(output() == Self.focusIn)
        #expect(host.setFocused(false) == true)
        #expect(output() == Self.focusIn + Self.focusOut)
    }

    /// A child that never enabled 1004 is not written to. A shell pane at a
    /// bare prompt is this case, and writing `ESC [ O` into it would put
    /// literal junk on someone's command line.
    @MainActor @Test func aChildThatDidNotAskGetsNothing() {
        let (host, output) = host(focusMode: false)
        #expect(host.setFocused(true) == false)
        #expect(host.setFocused(false) == false)
        #expect(output().isEmpty)
    }

    /// A repeat is not sent. AppKit is generous with key-window
    /// notifications — a sheet, a menu, a space switch — and the harness
    /// pulses presence *on* focus-gained, so a duplicate report is a
    /// duplicate pulse to Anthropic.
    @MainActor @Test func aRepeatIsNotSent() {
        let (host, output) = host(focusMode: true)
        #expect(host.setFocused(true) == true)
        #expect(host.setFocused(true) == false)
        #expect(host.setFocused(true) == false)
        #expect(output() == Self.focusIn)
    }

    /// **The attach case, and the reason the desire is held rather than
    /// dropped.** A pane mounts before its child has started, so the first
    /// report cannot be written; if that counted as sent, a session
    /// attached while the window was not key would never afterwards be
    /// able to say nobody is watching — and the harness would suppress the
    /// user's phone for a pane no one is looking at. The pending report
    /// goes out on the read that turns the mode on.
    @MainActor @Test func aReportMadeBeforeTheChildWasListeningLandsLater() {
        let (host, output) = host(focusMode: false)
        #expect(host.setFocused(false) == false)
        #expect(output().isEmpty)
        host.feed(Data("\u{1b}[?1004h".utf8))
        #expect(output() == Self.focusOut, "the blur should land on the chunk that enabled 1004")
    }

    /// And the same path does not fire twice: once the pending report has
    /// landed, further output from the child changes nothing.
    @MainActor @Test func theLandedReportIsNotRepeatedByMoreOutput() {
        let (host, output) = host(focusMode: false)
        host.setFocused(false)
        host.feed(Data("\u{1b}[?1004h".utf8))
        host.feed(Data("hello".utf8))
        host.feed(Data("world".utf8))
        #expect(output() == Self.focusOut)
    }

    /// A child that turns the mode back off stops being told. Symmetric
    /// with `paste` and 2004: the mode is read from the core every time,
    /// never cached, so a mid-session change is answered.
    @MainActor @Test func aChildThatTurnsTheModeOffIsNoLongerTold() {
        let (host, output) = host(focusMode: true)
        host.setFocused(true)
        host.feed(Data("\u{1b}[?1004l".utf8))
        #expect(host.setFocused(false) == false)
        #expect(output() == Self.focusIn)
    }
}
