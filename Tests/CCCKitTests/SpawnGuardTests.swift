import Foundation
import Testing

@testable import CCCKit

/// Item 19: the two refusals the spawner makes, both of them re-enacting a
/// thing that happened. The name guard's fixture is 2026-09-06's twenty
/// minutes of two `att-capture` jobs in one lane worktree; the space
/// guard's is 2026-09-04 23:13Z, when the Mac locked under a 27.6 GB test
/// suite on a disk that had nothing left to swap into.
@Suite struct SpawnGuardTests {
    private static func row(_ name: String?, _ state: Session.State?, cwd: String,
                            id: String, host: String = Host.localName,
                            started: TimeInterval = 0) -> SessionRow {
        SessionRow(session: Session(id: id, cwd: cwd, kind: .background,
                                    startedAt: Date(timeIntervalSince1970: 1_757_000_000 + started),
                                    state: state, name: name),
                   host: host, model: nil, attached: false)
    }

    // MARK: the name

    /// The 09-06 shape exactly: the daemon still holds Friday's job, the
    /// commander asks for the same name in the same lane worktree.
    @Test func aLiveNamesakeInTheSameLaneIsRefused() {
        let lane = "/Users/rf-studio/code/fun/attrition/.claude/worktrees/lane-capture"
        let rows = [Self.row("att-capture", .working, cwd: lane, id: "7f476e34")]
        let request = SpawnRequest(cwd: lane, prompt: "capture the run", name: "att-capture")
        let held = SpawnGuard.nameHolder(for: request, on: Host.localName, cwd: lane, rows: rows)
        #expect(held?.ref == SessionRef(host: Host.localName, id: "7f476e34"))
        #expect(held?.sameFolder == true)
        // The refusal has to be actionable, not just correct.
        #expect(held!.said.contains("ccc stop"))
        #expect(held!.said.contains("--replace"))
        #expect(held!.said.contains("--allow-duplicate"))
    }

    /// The name alone is the predicate. A namesake in another folder
    /// mis-routes every message exactly as badly — `SendMessage`, the lore
    /// thread and the roster all resolve by name — so the folder changes
    /// only what the refusal says, never whether it refuses.
    @Test func aLiveNamesakeElsewhereIsStillRefused() {
        let rows = [Self.row("att-capture", .blocked, cwd: "/Users/rf-studio/code/fun/attrition", id: "aaaa1111")]
        let request = SpawnRequest(cwd: "/Users/rf-studio/code/fun/attrition/.claude/worktrees/lane-capture",
                                   name: "att-capture")
        let held = SpawnGuard.nameHolder(for: request, on: Host.localName, cwd: request.cwd, rows: rows)
        #expect(held != nil)
        #expect(held?.sameFolder == false)
        #expect(held!.said.contains("/Users/rf-studio/code/fun/attrition"))
    }

    /// And the converse does not hold: a *second session in a folder* is
    /// ordinary. The 09-06 roster carried six rows under
    /// `~/code/work/cuanto`, and refusing that would break the commonest
    /// thing anyone does — start a quick session where the work is.
    @Test func aSharedFolderWithADifferentNameIsNotARefusal() {
        let repo = "/Users/rf-studio/code/work/cuanto"
        let rows = [Self.row("storefront-launch", .working, cwd: repo, id: "58023208")]
        let request = SpawnRequest(cwd: repo, name: "annotate")
        #expect(SpawnGuard.nameHolder(for: request, on: Host.localName, cwd: repo, rows: rows) == nil)
        // Nor is an unnamed spawn ever refused: it has no address to lose.
        #expect(SpawnGuard.nameHolder(for: SpawnRequest(cwd: repo), on: Host.localName, cwd: repo, rows: rows) == nil)
    }

    /// Re-using a finished lane's name is the normal thing a commander
    /// does, and `--all` keeps every dead namesake forever — the same
    /// roster held two `beta-fb-polish` and two `beta-fb-metadata` in
    /// ended states. Only a job that can still receive a message counts.
    @Test func endedNamesakesDoNotHoldTheName() {
        let cwd = "/Users/rf-studio/code/work/cuanto/.claude/worktrees/beta-fb-polish"
        for state in [Session.State.done, .failed, .stopped] {
            let rows = [Self.row("beta-fb-polish", state, cwd: cwd, id: "97c4731d")]
            #expect(SpawnGuard.nameHolder(for: SpawnRequest(cwd: cwd, name: "beta-fb-polish"),
                                          on: Host.localName, cwd: cwd, rows: rows) == nil,
                    "\(state.rawValue) should not hold the name")
        }
        // A state ccc does not know is live: the lenient boundary rule
        // says a shape we cannot read is running, not finished.
        #expect(SpawnGuard.isLive(nil))
    }

    /// The refusal names the job a message would reach *today* — the
    /// newest namesake — because that is the one by-name routing already
    /// resolves to.
    @Test func theNewestNamesakeIsTheOneNamed() {
        let rows = [Self.row("lane", .working, cwd: "/a", id: "old", started: 0),
                    Self.row("lane", .blocked, cwd: "/b", id: "new", started: 600)]
        let held = SpawnGuard.nameHolder(for: SpawnRequest(name: "lane"), on: Host.localName, cwd: nil, rows: rows)
        #expect(held?.ref.id == "new")
    }

    /// The roster crosses the hop, so the guard must not refuse a studio
    /// spawn because air holds the name.
    @Test func aNamesakeOnAnotherHostIsAnotherHostsProblem() {
        let rows = [Self.row("lane", .working, cwd: "/a", id: "x", host: "studio")]
        #expect(SpawnGuard.nameHolder(for: SpawnRequest(name: "lane"), on: Host.localName, cwd: nil, rows: rows) == nil)
        #expect(SpawnGuard.nameHolder(for: SpawnRequest(name: "lane"), on: "studio", cwd: nil, rows: rows) != nil)
    }

    @Test func trailingSlashesAreTheSameFolder() {
        #expect(SpawnGuard.sameFolder("/a/b", "/a/b/"))
        #expect(SpawnGuard.sameFolder("/", "/"))
        #expect(!SpawnGuard.sameFolder("/a/b", "/a/bc"))
    }

    // MARK: the disk

    @Test func aDiskUnderTheFloorIsRefusedAndSaysWhatToClear() {
        let tight = SpawnGuard.Space(freeBytes: 3 * 1_073_741_824, path: "/System/Volumes/Data")
        let refusal = SpawnGuard.spaceRefusal(tight, floorGB: 10)
        #expect(refusal != nil)
        #expect(refusal!.contains("3.0 GB free"))
        #expect(refusal!.contains("/System/Volumes/Data"))
        #expect(refusal!.contains("--no-space-check"))
    }

    @Test func aRoomyDiskAnUnreadableOneAndAZeroFloorAllPass() {
        let roomy = SpawnGuard.Space(freeBytes: 400 * 1_073_741_824, path: "/")
        #expect(SpawnGuard.spaceRefusal(roomy, floorGB: 10) == nil)
        // A volume ccc cannot read is never a refusal.
        #expect(SpawnGuard.spaceRefusal(nil, floorGB: 10) == nil)
        // 0 turns the floor off, which is what CCC_SPAWN_FLOOR_GB=0 means.
        #expect(SpawnGuard.spaceRefusal(SpawnGuard.Space(freeBytes: 0, path: "/"), floorGB: 0) == nil)
    }

    @Test func theFloorIsTenGBAndTheEnvironmentMovesIt() {
        #expect(SpawnGuard.floorGB(environment: [:]) == 10)
        #expect(SpawnGuard.floorGB(environment: ["CCC_SPAWN_FLOOR_GB": "25"]) == 25)
        #expect(SpawnGuard.floorGB(environment: ["CCC_SPAWN_FLOOR_GB": "0"]) == 0)
        // Nonsense falls back rather than disabling the guard by accident.
        #expect(SpawnGuard.floorGB(environment: ["CCC_SPAWN_FLOOR_GB": "lots"]) == 10)
        #expect(SpawnGuard.floorGB(environment: ["CCC_SPAWN_FLOOR_GB": "-5"]) == 10)
    }

    /// The real volume answers, whatever it says — this is the join
    /// between the pure rule above and the filesystem.
    @Test func theVolumeUnderAPathIsReadable() {
        let space = SpawnGuard.space(at: FileManager.default.currentDirectoryPath)
        #expect(space != nil)
        #expect((space?.freeBytes ?? 0) > 0)
    }

    // MARK: the verb `--replace` needs

    @Test func stopIsClaudeStopBehindTheHostsPrefix() {
        let local = ClaudeCLI(executable: "/Users/x/.local/bin/claude")
        #expect(local.stopArgv(id: "7f476e34") == ["/Users/x/.local/bin/claude", "stop", "7f476e34"])
        let remote = ClaudeCLI(executable: "~/.local/bin/claude",
                               host: Host(name: "studio", ssh: "studio", claude: "~/.local/bin/claude",
                                          home: "/Users/rf-studio"))
        let argv = remote.stopArgv(id: "7f476e34")
        #expect(argv.first == "/usr/bin/ssh")
        #expect(argv.suffix(3) == ["~/.local/bin/claude", "stop", "7f476e34"])
    }
}
