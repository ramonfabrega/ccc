import Foundation
import Testing

@testable import CCCKit

/// The ⌘-click gesture's reading (v7 slice 2). Pure over a `Grid`, so these
/// build one by hand the way `LeaveGestureTests` does.
@Suite struct LinkScannerTests {
    private func grid(_ lines: [String], cols: Int = 80) -> Grid {
        let padded = lines.map { $0.padding(toLength: cols, withPad: " ", startingAt: 0) }
        return Grid(cols: cols, rows: padded.count, lines: padded,
                    cursor: .init(col: 0, row: 0, visible: false))
    }

    @Test func theUrlThatStartedThis() {
        // The line that found the gap: a hook's answer in the pane.
        let g = grid(["Mirrored to https://cdn.ramonfabrega.com/sent/attached-drag-ba8f3c.png"])
        let found = LinkScanner.links(in: g)
        #expect(found.count == 1)
        #expect(found.first?.text == "https://cdn.ramonfabrega.com/sent/attached-drag-ba8f3c.png")
    }

    @Test func aClickLandsOnlyInsideTheSpan() {
        let g = grid(["see https://example.com/x here"])
        // "see " is columns 0..<4, the URL 4..<26.
        #expect(LinkScanner.link(in: g, atColumn: 0, row: 0) == nil)
        #expect(LinkScanner.link(in: g, atColumn: 4, row: 0)?.text == "https://example.com/x")
        #expect(LinkScanner.link(in: g, atColumn: 20, row: 0)?.text == "https://example.com/x")
        #expect(LinkScanner.link(in: g, atColumn: 40, row: 0) == nil)
    }

    @Test func sentencePunctuationIsNotTheUrl() {
        for (line, want) in [
            ("go to https://example.com/a.", "https://example.com/a"),
            ("go to https://example.com/a, then", "https://example.com/a"),
            ("go to https://example.com/a!", "https://example.com/a"),
            ("(see https://example.com/a)", "https://example.com/a"),
            ("\"https://example.com/a\"", "https://example.com/a"),
        ] {
            let found = LinkScanner.links(in: grid([line]))
            #expect(found.first?.text == want, "\(line)")
        }
    }

    @Test func bracketsTheUrlOpenedAreKept() {
        // Balanced parens belong to the URL — wikipedia's shape.
        let g = grid(["https://en.wikipedia.org/wiki/Foo_(bar)"])
        #expect(LinkScanner.links(in: g).first?.text == "https://en.wikipedia.org/wiki/Foo_(bar)")
    }

    @Test func onlyTheThreeSchemes() {
        let g = grid(["mailto:a@b.com ftp://x/y javascript:alert(1) https://ok.example/"])
        let found = LinkScanner.links(in: g)
        #expect(found.count == 1)
        #expect(found.first?.text == "https://ok.example/")
    }

    @Test func aSchemeWithNothingAfterItIsNotALink() {
        #expect(LinkScanner.links(in: grid(["https:// and http://"])).isEmpty)
    }

    @Test func severalOnOneRowInReadingOrder() {
        let g = grid(["https://a.example/1 and https://b.example/2"])
        let found = LinkScanner.links(in: g)
        #expect(found.map(\.text) == ["https://a.example/1", "https://b.example/2"])
        #expect(found[0].columns.lowerBound == 0)
        #expect(found[1].columns.lowerBound == 24)
    }

    @Test func rowsAreReportedAsTheyAreClicked() {
        let g = grid(["nothing here", "https://example.com/second-row"])
        let found = LinkScanner.links(in: g)
        #expect(found.count == 1)
        #expect(found.first?.row == 1)
        #expect(LinkScanner.link(in: g, atColumn: 3, row: 1)?.row == 1)
        #expect(LinkScanner.link(in: g, atColumn: 3, row: 0) == nil)
    }

    @Test func fileUrlsCount() {
        // An agent's output names local paths constantly; `file://` has no
        // host, which is why the scan does not require one for it.
        let g = grid(["wrote file:///Users/x/report.md"])
        #expect(LinkScanner.links(in: g).first?.text == "file:///Users/x/report.md")
    }

    @Test func aWrappedUrlStopsAtItsRow() {
        // The documented limit: without a soft-wrap flag the second row is
        // not joined. Better a short URL than one with prose glued to it.
        let g = grid(["https://example.com/a-very-long", "path/that/continued"], cols: 31)
        let found = LinkScanner.links(in: g)
        #expect(found.count == 1)
        #expect(found.first?.text == "https://example.com/a-very-long")
    }

    @Test func offGridRowsAreNil() {
        let g = grid(["https://example.com/x"])
        #expect(LinkScanner.link(in: g, atColumn: 0, row: 5) == nil)
        #expect(LinkScanner.link(in: g, atColumn: 0, row: -1) == nil)
    }
}
