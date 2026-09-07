import Foundation
import Testing

@testable import CCCKit

/// A `<ref>` resolves by id **or by name**, reported by lore 2026-09-07:
/// `ccc clear lore` said "no session 'lore' in the roster" in the same
/// second `ccc list` drew the row, because the verbs ccc resolves itself
/// matched the id alone while the verbs it hands to `claude` — stop,
/// send, attach — took a name for free. Half a verb list is the shape
/// this repo's own rule warns about (`docs/DESIGN.md` §9, "a verb with
/// fewer surfaces than its opposite will be reported missing").
///
/// Fixtures, never a live row: a roster row is stale the instant it
/// prints, and a test that reads one is a test that races the fleet.
@Suite struct RefLookupTests {
    private func row(_ id: String, name: String? = nil) -> Session {
        Session(id: id, cwd: "/x", kind: .background, startedAt: Date(), name: name)
    }

    @Test func aNameResolvesTheWayAnIdDoes() throws {
        let roster = [row("a18a763f", name: "lore"), row("3c382923", name: "attrition")]
        #expect(try roster.session(matching: "a18a763f").name == "lore")
        #expect(try roster.session(matching: "lore").id == "a18a763f")
        #expect(try roster.session(matching: "attrition").id == "3c382923")
    }

    /// The id wins, always. An id is minted unique and a name is not, so a
    /// name shaped like another row's id must never shadow that row —
    /// otherwise `ccc clear <id>` could clear something else entirely.
    @Test func theIdWinsOverANameThatLooksLikeOne() throws {
        let roster = [row("a18a763f", name: "lore"), row("3c382923", name: "a18a763f")]
        #expect(try roster.session(matching: "a18a763f").name == "lore")
    }

    /// Two live rows under one name is a real state — `ccc spawn` refuses
    /// a duplicate live name, and `--allow-duplicate` means it — so it is
    /// named rather than guessed at: picking one would clear, archive or
    /// merge the wrong session.
    @Test func anAmbiguousNameIsNamedAndNotGuessed() {
        let roster = [row("a1b2c3d4", name: "worker"), row("e5f6a7b8", name: "worker")]
        #expect(throws: RefLookupError.ambiguousName("worker", ["a1b2c3d4", "e5f6a7b8"])) {
            try roster.session(matching: "worker")
        }
        #expect(RefLookupError.ambiguousName("worker", ["a1b2c3d4", "e5f6a7b8"]).description
                == "'worker' is the name of 2 live sessions (a1b2c3d4, e5f6a7b8); use an id")
        // …and the ids still resolve, since only the name is ambiguous.
        #expect((try? roster.session(matching: "e5f6a7b8"))?.id == "e5f6a7b8")
    }

    @Test func nothingMatchingIsTheSameSentenceItAlwaysWas() {
        let roster = [row("a18a763f", name: "lore")]
        #expect(throws: RefLookupError.noSuchSession("ghost")) {
            try roster.session(matching: "ghost")
        }
        #expect(RefLookupError.noSuchSession("ghost").description == "no session 'ghost' in the roster")
        // A row with no name at all is not a row a nil name can match.
        #expect((try? [row("a18a763f")].session(matching: "lore")) == nil)
    }

    /// `claude rm`'s cwd read is the one lookup where absence is ordinary
    /// — it works on a session the roster has already forgotten — so it
    /// answers nil rather than throwing, ambiguity included.
    @Test func theNonFatalHalfAnswersNilOnBothFailures() {
        let roster = [row("a1b2c3d4", name: "worker"), row("e5f6a7b8", name: "worker")]
        #expect(roster.sessionIfAny(matching: "worker") == nil)
        #expect(roster.sessionIfAny(matching: "ghost") == nil)
        #expect(roster.sessionIfAny(matching: "a1b2c3d4")?.id == "a1b2c3d4")
    }
}
