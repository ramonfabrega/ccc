import Foundation
import Testing

@testable import CCCKit

/// Queue item 3's last step: the picker's data half — what Macs are on the
/// tailnet, so adding one does not mean looking up an address.
///
/// Driven from a **real** `tailscale status --json`, captured 2026-09-04
/// (`Fixtures/tailnet/status-2026-09-04.json`, trimmed to the fields we read
/// so no key material is banked). A hand-written blob would agree with
/// whatever this file assumed; the capture is what says `HostName` is
/// "localhost" for an iPhone and that a dead Mac carries `Expired`.
@Suite struct TailnetTests {
    private func peers() throws -> [Tailnet.Peer] {
        try Tailnet.peers(from: Fixtures.data("tailnet/status-2026-09-04.json"))
    }

    /// The whole filter in one assertion. Six nodes go in: this Mac, air,
    /// a dead Mac, an iPhone and two tagged Linux boxes. Two come out.
    @Test func onlyLiveMacsAreOffered() throws {
        let offered = try peers()
        #expect(offered.map(\.name) == ["air", "studio"])
    }

    /// **The name is the first label of `DNSName`, not `HostName`.** The
    /// capture is what makes this a fact rather than a preference: the Macs
    /// call themselves "Ramon's Mac Studio" and "Ramon's MacBook Air" —
    /// which have spaces and a smart apostrophe, so they are not legal host
    /// names — and the iPhone calls itself "localhost".
    @Test func theNameIsTheMagicDNSLabel() throws {
        let studio = try #require(try peers().first { $0.isSelf })
        #expect(studio.name == "studio")
        #expect(studio.dnsName == "studio.bengal-barb.ts.net")   // trailing dot gone
        #expect(studio.hostName == "Ramon\u{2019}s Mac Studio")
        // The label survives `Host.validate`, which the machine's own name
        // would not: it is what gets written to hosts.json.
        #expect(Host(name: studio.name, ssh: studio.name, claude: "/usr/bin/claude").validate() == nil)
        #expect(Host(name: studio.hostName, ssh: studio.name, claude: "/usr/bin/claude").validate() != nil)
    }

    /// This Mac is listed, not hidden. Registering yourself is the loopback
    /// hop — it carries the real client code and the real sshd — and is how
    /// the remote path is exercised from one machine.
    @Test func thisMacIsOfferedToo() throws {
        let selves = try peers().filter(\.isSelf)
        #expect(selves.map(\.name) == ["studio"])
    }

    /// mbp is dropped for a reason a machine can check — its node key
    /// expired 2025-07-26 — rather than for looking old. `LastSeen` alone
    /// would have been a threshold someone has to pick.
    @Test func anExpiredNodeIsDroppedForARealReason() throws {
        let live = try peers()
        #expect(live.allSatisfy { $0.name != "mbp" })
        // …and it is `Expired` doing it, not the date: the same node without
        // that flag is a legitimate, merely-offline candidate.
        let revived = try Data(contentsOf: Fixtures.url("tailnet/status-2026-09-04.json"))
        let text = String(decoding: revived, as: UTF8.self)
            .replacingOccurrences(of: "\"Expired\": true", with: "\"Expired\": false")
        let unexpired = try Tailnet.peers(from: Data(text.utf8))
        let mbp = try #require(unexpired.first { $0.name == "mbp" })
        #expect(mbp.online == false)
        #expect(mbp.lastSeen != nil)
    }

    /// Online first, then by name, so the machine you want is at the top.
    ///
    /// **Only `Self` reports the zero date.** An online *peer* still carries
    /// a real `LastSeen` — air's is minutes old — so "has a lastSeen" is not
    /// the same question as "is offline", and only `Online` answers the
    /// second. The zero date still has to become nil rather than a `Date`:
    /// `0001-01-01` would sort and print as the oldest thing on the tailnet.
    @Test func liveOnesSortFirstAndOnlySelfHasNoLastSeen() throws {
        let listed = try peers()
        #expect(listed.allSatisfy { $0.online })
        #expect(listed.map(\.name) == listed.map(\.name).sorted())

        let studio = try #require(listed.first { $0.isSelf })
        #expect(studio.lastSeen == nil, "the zero date must not survive as a Date")
        let air = try #require(listed.first { !$0.isSelf })
        #expect(air.online)
        #expect(air.lastSeen != nil, "an online peer still dates itself")
    }

    /// The boundary rule, applied to another program's undocumented output:
    /// garbage is an error, a shape change is not a crash, and a node
    /// missing the fields we need is dropped rather than guessed at.
    @Test func aChangedShapeIsNeverACrash() throws {
        #expect(throws: (any Error).self) {
            try Tailnet.peers(from: Data("not json".utf8))
        }
        let empty = try Tailnet.peers(from: Data("{}".utf8))
        #expect(empty.isEmpty)
        let noName = try Tailnet.peers(from: Data(#"{"Self":{"OS":"macOS","Online":true}}"#.utf8))
        #expect(noName.isEmpty)
        // Unknown keys are ignored, not fatal — the roster's rule.
        let extra = #"{"Self":{"OS":"macOS","Online":true,"DNSName":"a.b.ts.net.","SomethingNew":42}}"#
        let parsed = try Tailnet.peers(from: Data(extra.utf8))
        #expect(parsed.map(\.name) == ["a"])
    }

    /// A name that could not be written to `hosts.json` is not offered: it
    /// would fail `Host.validate` at add time anyway, and `:` is what
    /// separates host from id in `ccc attach host:id`.
    @Test func anUnusableLabelIsDropped() throws {
        let colon = try Tailnet.peers(from: Data(#"{"Self":{"OS":"macOS","Online":true,"DNSName":"a:b.c.ts.net."}}"#.utf8))
        #expect(colon.isEmpty)
        let blank = try Tailnet.peers(from: Data(#"{"Self":{"OS":"macOS","Online":true,"DNSName":"."}}"#.utf8))
        #expect(blank.isEmpty)
    }
}
