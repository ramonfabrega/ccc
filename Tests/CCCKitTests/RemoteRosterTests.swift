import Foundation
import Testing

@testable import CCCKit

/// The model column over ssh. It is a join against the session's transcript
/// *file*, so it can only happen where that filesystem is — which is why a
/// remote host's roster is read by the far side's own `ccc list --json`
/// rather than by tailing 17 files across the hop. These pin the contract
/// between the two builds of ccc that now talk to each other.
@Suite struct RemoteRosterTests {
    private let remoteHost = Host(name: "studio", ssh: "studio",
                                  claude: "~/.local/bin/claude", ccc: "~/.local/bin/ccc")

    @Test func aRemoteHostWithCCCReadsThroughOurOwnTwin() {
        let cli = ClaudeCLI(executable: "~/.local/bin/claude", host: remoteHost)
        #expect(cli.rosterSource == .ccc)
        // `--host local`, or the far side would poll every host *it* knows —
        // which may include us, which would poll it, which…
        #expect(cli.rosterArgv().suffix(5) == ["~/.local/bin/ccc", "list", "--json", "--host", "local"])
        // Still one round trip on the shared master, like every other call.
        #expect(cli.rosterArgv().contains("ControlPath=\(cli.sshControlPath)"))
        #expect(!cli.rosterArgv().contains("-t"))
    }

    @Test func withoutCCCItFallsBackToTheHarnessReader() {
        let host = Host(name: "air", ssh: "air", claude: "~/.local/bin/claude")
        let cli = ClaudeCLI(executable: "~/.local/bin/claude", host: host)
        #expect(cli.rosterSource == .claude)
        #expect(cli.rosterArgv().suffix(3) == ["agents", "--json", "--all"])
    }

    /// Locally we are already the process that does the join; shelling out
    /// to ourselves would spawn a second one to do the same work.
    @Test func localNeverShellsOutToItself() {
        let cli = ClaudeCLI(executable: "/usr/local/bin/claude",
                            host: Host(name: "local", ccc: "/usr/local/bin/ccc"))
        #expect(cli.rosterSource == .claude)
    }

    // MARK: the wire between two builds of ccc

    /// What `ccc list --json` writes must be what the poller reads back.
    /// The trap is dates: `startedAt` goes out ISO-8601 and the default
    /// decoding strategy would read that string as a number and throw.
    @Test func rowsSurviveTheRoundTripTheCLIActuallyWrites() throws {
        let session = Session(id: "a1b2", cwd: "/Users/x/code", kind: .background,
                              startedAt: Date(timeIntervalSince1970: 1_756_800_000),
                              state: .working, status: .busy, sessionId: "dbdad1ef", name: "lore")
        let row = SessionRow(session: session, model: "claude-opus-5", attached: false)

        // Exactly the encoder `CLI.printJSON` uses.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let decoded = try JSONDecoder.roster.decode([SessionRow].self, from: encoder.encode([row]))
        #expect(decoded.count == 1)
        #expect(decoded[0].model == "claude-opus-5")
        #expect(decoded[0].session.id == "a1b2")
        #expect(decoded[0].session.startedAt == session.startedAt)
        #expect(decoded[0].session.state == .working)
    }

    /// The far side may be an older ccc: a v1 build writes no `host` key.
    /// That must decode, not throw — the poller re-stamps the host anyway,
    /// since which machine answered is this process's knowledge.
    @Test func aRowFromAnOlderCCCStillDecodes() throws {
        let json = """
        [{"session":{"id":"a1b2","cwd":"/Users/x","kind":"background",
          "startedAt":"2026-09-02T07:20:04Z","extra":{}},"model":"claude-opus-5"}]
        """
        let rows = try JSONDecoder.roster.decode([SessionRow].self, from: Data(json.utf8))
        #expect(rows.count == 1)
        #expect(rows[0].host == Host.localName)   // the fallback
        #expect(rows[0].attached == false)
        #expect(rows[0].model == "claude-opus-5")
    }

    /// The far side is the build that learns a new word first (studio runs
    /// the dev loop; air pulls releases). A `status` this build has never
    /// heard of parks in `extra` and the row stands; a row with no `id`
    /// costs that row and names itself; the rest of the array arrives.
    /// Until 2026-09-04 either threw the whole host away as stale.
    @Test func aWordFromANewerCCCDoesNotCostTheHost() throws {
        let json = """
        [{"session":{"id":"a1b2","cwd":"/Users/x","kind":"background","startedAt":"2026-09-02T07:20:04Z",
          "status":"parked"}},
         {"session":{"cwd":"/Users/y","kind":"background","startedAt":"2026-09-02T07:20:04Z","extra":{}}},
         {"session":{"id":"c3d4","cwd":"/Users/z","kind":"background","startedAt":"2026-09-02T07:20:04Z",
          "state":"working","extra":{}},"model":"claude-opus-5"}]
        """
        let elements = try JSONDecoder.roster.decode([LenientElement<SessionRow>].self, from: Data(json.utf8))
        #expect(elements.count == 3)
        let first = try #require(elements[0].value)
        #expect(first.session.status == nil)
        #expect(first.session.extra["status"] == .string("parked"))
        #expect(elements[1].value == nil)
        #expect(elements[1].error?.contains("id") == true, "the reason names the field: \(elements[1].error ?? "")")
        #expect(elements[2].value?.model == "claude-opus-5")
        #expect(elements[2].value?.session.state == .working)
    }

    /// A remote row is addressed by the host that answered, never by the
    /// `local` the far side wrote about itself.
    @Test func theHostIsRestampedByWhoeverAsked() throws {
        let json = """
        [{"session":{"id":"a1b2","cwd":"/Users/x","kind":"background",
          "startedAt":"2026-09-02T07:20:04Z","extra":{}},"host":"local","attached":true}]
        """
        var row = try JSONDecoder.roster.decode([SessionRow].self, from: Data(json.utf8))[0]
        #expect(row.ref == SessionRef(id: "a1b2"))
        row.host = "studio"
        #expect(row.ref == SessionRef(host: "studio", id: "a1b2"))
        #expect(row.ref.description == "studio:a1b2")
    }

    // MARK: the probe

    /// The first real host (2026-09-02) found `claude` where its installer
    /// puts it and `ccc` where ccc's install script puts it — two different
    /// directories. The probe asks; the parser reads what it said.
    @Test func theProbeReadsWhatTheHostAnswered() {
        let probe = ClaudeCLI.Probe.parse("""
        home=/Users/rf-studio
        claude=/Users/rf-studio/.local/bin/claude
        ccc=/opt/homebrew/bin/ccc
        """)
        #expect(probe == ClaudeCLI.Probe(home: "/Users/rf-studio", claude: "/Users/rf-studio/.local/bin/claude",
                                         ccc: "/opt/homebrew/bin/ccc"))
        // A missing binary is simply absent; a missing home is no answer.
        #expect(ClaudeCLI.Probe.parse("home=/Users/x\n")?.ccc == nil)
        #expect(ClaudeCLI.Probe.parse("claude=/c\n") == nil)
        // Shell noise (a motd, a warning) does not confuse it.
        #expect(ClaudeCLI.Probe.parse("Last login: today\nhome=/Users/x\nzsh: warning=foo\n")?.home == "/Users/x")
    }

    /// The words go through the remote login shell unquoted, so every
    /// candidate `~` expands there — and none of them may carry a quote.
    @Test func theProbeWordsAreShellSafeAndExpandTilde() {
        let words = ClaudeCLI.Probe.words
        #expect(words.contains("~/.local/bin/claude"))
        #expect(words.contains("/opt/homebrew/bin/ccc"))
        #expect(!words.contains { $0.contains("'") || $0.contains("\"") })
    }

    @Test func aCCCPathNeedingQuotesIsRefusedLikeTheClaudeOne() {
        let host = Host(name: "studio", ssh: "studio", claude: "/c", ccc: "/opt/my ccc/bin/ccc")
        #expect(host.validate()?.contains("ccc path") == true)
    }
}
