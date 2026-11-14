import Foundation
import Testing

@testable import CCCKit

/// `TypeAhead`: what is typed while a clicked session is on its way.
@Suite struct TypeAheadTests {
    @Test func keysTypedDuringTheWaitAreHandedOverInOrder() {
        var ahead = TypeAhead<String>()
        ahead.hold("x")
        #expect(!ahead.isOpen, "nothing is held when no attach is pending")
        let token = ahead.begin()
        #expect(ahead.isOpen)
        for key in ["t", "h", "e"] { ahead.hold(key) }
        #expect(ahead.end(token) == ["t", "h", "e"])
        #expect(!ahead.isOpen)
        #expect(ahead.end(token) == nil, "an attach ends once")
    }

    /// A second click supersedes the first: the first's keys were meant
    /// for its session and go nowhere, and its ending hands over nothing.
    @Test func aNewerClickOwnsTheKeyboard() {
        var ahead = TypeAhead<String>()
        let first = ahead.begin()
        ahead.hold("a")
        let second = ahead.begin()
        ahead.hold("b")
        #expect(ahead.end(first) == nil)
        #expect(ahead.isOpen, "the newer attach is still pending")
        #expect(ahead.end(second) == ["b"])
    }

    @Test func aStuckKeyIsBounded() {
        var ahead = TypeAhead<Int>()
        let token = ahead.begin()
        for n in 0..<1000 { ahead.hold(n) }
        #expect(ahead.end(token)?.count == TypeAhead<Int>.limit)
    }
}
