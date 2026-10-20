import Foundation
import Testing

@testable import CCCKit

/// The two links between ccc and lore (2026-10-20): `ccc://attach/<ref>`
/// in, `<lore>/job/<id>` out. The grammar is what lore emits, so these
/// tests read the exact strings lore was told.
@Suite struct CrossLinkTests {
    // MARK: resolve — what `ccc attach`, a click and a link all go through

    static func state(_ hosts: [String: [(id: String, name: String?)]]) -> RosterPoller.State {
        RosterPoller.State(hosts: hosts.keys.sorted().map { host in
            var poll = HostPoll(host: host)
            poll.rows = hosts[host]!.map {
                SessionRow(session: Session(id: $0.id, cwd: "/", kind: .background, startedAt: Date(), state: .done, name: $0.name),
                           host: host, model: nil, attached: false)
            }
            return poll
        })
    }

    @Test func aBareIdThisMacHasStaysLocal() throws {
        let s = Self.state([Host.localName: [("a1b2", "lore")], "studio": [("a1b2", nil)]])
        #expect(try s.resolve(SessionRef(id: "a1b2")) == SessionRef(id: "a1b2"))
    }

    /// The case the link exists for: lore on studio emits a bare daemon
    /// id, and on air only the `studio` row has it.
    @Test func aBareIdOnlyAnotherHostHasAttachesThere() throws {
        let s = Self.state([Host.localName: [("ffff", nil)], "studio": [("d573a0e9", "lore")]])
        #expect(try s.resolve(SessionRef(id: "d573a0e9")) == SessionRef(host: "studio", id: "d573a0e9"))
        #expect(try s.resolve(SessionRef(id: "lore")) == SessionRef(host: "studio", id: "d573a0e9"))
    }

    @Test func aNameResolvesToItsId() throws {
        let s = Self.state([Host.localName: [("a1b2", "lore")]])
        #expect(try s.resolve(SessionRef(id: "lore")) == SessionRef(id: "a1b2"))
        #expect(try s.resolve(SessionRef(host: Host.localName, id: "lore")) == SessionRef(id: "a1b2"))
    }

    /// The id wins over a name across hosts as it does within one: a row
    /// on one host *named* like another host's id never shadows it.
    @Test func anIdOnOneHostBeatsANameOnAnother() throws {
        let s = Self.state(["air2": [("zzzz", "d573a0e9")], "studio": [("d573a0e9", nil)]])
        #expect(try s.resolve(SessionRef(id: "d573a0e9")) == SessionRef(host: "studio", id: "d573a0e9"))
    }

    @Test func twoHostsAnsweringIsRefusedWithBoth() {
        let s = Self.state(["mini": [("lore1", "lore")], "studio": [("lore2", "lore")]])
        #expect(throws: RefLookupError.ambiguousHost("lore", ["mini:lore1", "studio:lore2"])) {
            try s.resolve(SessionRef(id: "lore"))
        }
    }

    @Test func aHostQualifiedRefLooksOnThatHostAlone() throws {
        let s = Self.state([Host.localName: [("a1b2", "lore")], "studio": [("c3d4", "lore")]])
        #expect(try s.resolve(SessionRef(host: "studio", id: "lore")) == SessionRef(host: "studio", id: "c3d4"))
    }

    /// No roster has it: the word goes through to `claude attach` as it
    /// always did, and the harness says what it says.
    @Test func aRefNoRosterHasIsUnchanged() throws {
        let s = Self.state([Host.localName: [("a1b2", nil)], "studio": [("c3d4", nil)]])
        #expect(try s.resolve(SessionRef(id: "nope")) == SessionRef(id: "nope"))
        #expect(try s.resolve(SessionRef(host: "gone", id: "x")) == SessionRef(host: "gone", id: "x"))
    }

    // MARK: ccc://attach/<ref>

    @Test func theGrammarLoreEmits() throws {
        #expect(try CCCURL.parse(URL(string: "ccc://attach/d573a0e9")!) == .attach(SessionRef(id: "d573a0e9")))
        #expect(try CCCURL.parse(URL(string: "ccc://attach/studio:d573a0e9")!) == .attach(SessionRef(host: "studio", id: "d573a0e9")))
        #expect(try CCCURL.parse(URL(string: "ccc://attach/keyboard%20handling%20issue")!)
            == .attach(SessionRef(id: "keyboard handling issue")))
        #expect(try CCCURL.parse(URL(string: "CCC://Attach/a1b2/")!) == .attach(SessionRef(id: "a1b2")))
    }

    @Test func whatIsNotALinkIsRefused() {
        for text in ["ccc://attach/", "ccc://attach", "ccc://attach/a/b", "ccc://open/a1b2", "https://attach/a1b2",
                     "ccc://attach/a:b:c"] {
            #expect(throws: CCCURL.Refusal.self, "\(text)") { try CCCURL.parse(URL(string: text)!) }
        }
    }

    @Test func theWriterIsTheReadersInverse() throws {
        for ref in [SessionRef(id: "a1b2"), SessionRef(host: "studio", id: "a1b2"), SessionRef(id: "a name/with slash")] {
            let link = CCCURL.attach(ref).url
            #expect(try CCCURL.parse(link) == .attach(ref), "\(link)")
        }
        #expect(CCCURL.attach(SessionRef(id: "a b")).url.absoluteString == "ccc://attach/a%20b")
    }

    // MARK: <lore>/job/<id>

    @Test func theJobLinkJoinsOnOneSlash() {
        let id = "d573a0e9"
        #expect(LoreLink.jobURL(base: URL(string: "http://100.81.87.24:4949/")!, id: id).absoluteString
            == "http://100.81.87.24:4949/job/d573a0e9")
        #expect(LoreLink.jobURL(base: URL(string: "http://h:4949")!, id: id).absoluteString == "http://h:4949/job/d573a0e9")
        #expect(LoreLink.jobURL(base: URL(string: "http://h/")!, id: "a b/c").absoluteString == "http://h/job/a%20b%2Fc")
    }

    /// The payload measured from `lore server status --json` on
    /// 2026-10-20, trimmed to what ccc reads plus a neighbour.
    @Test func theStatusPayloadIsReadForItsUrl() throws {
        let ok = #"{"label":"com.ramonfabrega.lore","url":"http://100.81.87.24:4949/","server":{"ok":true,"pid":85796}}"#
        #expect(try LoreLink.decodeStatus(Data(ok.utf8)).absoluteString == "http://100.81.87.24:4949/")
        let down = #"{"url":"http://100.81.87.24:4949/","server":{"ok":false,"error":"connection refused"}}"#
        #expect(throws: LoreLink.LookupError.notServing("connection refused")) { try LoreLink.decodeStatus(Data(down.utf8)) }
        #expect(throws: LoreLink.LookupError.self) { try LoreLink.decodeStatus(Data("lore v0.1.0".utf8)) }
    }

    @Test func aServerFileWhosePidIsGoneIsNoAnswer() throws {
        let file = Data(#"{"url":"http://h:4949/","pid":4242,"build":"b1"}"#.utf8)
        #expect(try LoreLink.decodeServerFile(file, alive: { _ in true }).absoluteString == "http://h:4949/")
        #expect(throws: LoreLink.LookupError.self) { try LoreLink.decodeServerFile(file, alive: { _ in false }) }
    }

    @Test func theOverrideWins() async throws {
        let url = try await LoreLink.serverURL(environment: ["CCC_LORE_URL": "http://x:1/"], home: "/nonexistent")
        #expect(url.absoluteString == "http://x:1/")
    }

    /// The GUI's PATH lacks the shim's `bun`: the child's PATH carries the
    /// shim's own directory first.
    @Test func theChildPathCarriesTheShimsDirectory() {
        let env = LoreLink.childEnvironment(lore: "/Users/u/.bun/bin/lore", environment: ["PATH": "/usr/bin:/bin"], home: "/Users/u")
        #expect(env["PATH"]?.hasPrefix("/Users/u/.bun/bin:") == true)
        #expect(env["PATH"]?.hasSuffix(":/usr/bin:/bin") == true)
    }
}
