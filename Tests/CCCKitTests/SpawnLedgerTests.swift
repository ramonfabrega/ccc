import Foundation
import Testing

@testable import CCCKit

/// The spawn ledger (lore's ask, 2026-11-13): a spawn's parent as a field
/// ccc writes, not a grep of the spawner's transcript. What these hold is
/// the contract lore indexes — the keys, the null, the one line per spawn
/// wherever stdout went — and that a ledger which cannot be written never
/// costs the spawn.
@Suite struct SpawnLedgerTests {
    /// The environment a `--bg` session hands its shells, as measured in
    /// one (2.1.321, job b87b7169, after a /clear).
    static let sessionEnvironment = [
        "CLAUDE_JOB_DIR": "/Users/x/.claude/jobs/b87b7169",
        "CLAUDE_CODE_SESSION_ID": "15a04072-8803-487d-a6d4-16b3eb76f048",
        "CLAUDE_CODE_BRIDGE_SESSION_ID": "session_01YYPbMRFLoY82q9xYDcFJjk",
        "CLAUDE_CODE_CHILD_SESSION": "1",
        "PATH": "/usr/bin",
    ]

    private func scratch() throws -> URL {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: the caller

    @Test func theCallerIsTheJobDirectorysLastWordAndTheTwoIdsBesideIt() throws {
        let caller = try #require(SpawnLedger.Caller.of(environment: Self.sessionEnvironment))
        #expect(caller.job == "b87b7169")
        #expect(caller.session == "15a04072-8803-487d-a6d4-16b3eb76f048")
        #expect(caller.bridge == "session_01YYPbMRFLoY82q9xYDcFJjk")
        // A trailing slash is still the same directory.
        #expect(SpawnLedger.Caller.of(environment: ["CLAUDE_JOB_DIR": "/Users/x/.claude/jobs/b87b7169/"])?.job == "b87b7169")
    }

    @Test func noSessionInTheEnvironmentIsNoCaller() {
        #expect(SpawnLedger.Caller.of(environment: ["PATH": "/usr/bin", "CLAUDE_EFFORT": "high"]) == nil)
        #expect(SpawnLedger.Caller.of(environment: ["CLAUDE_JOB_DIR": "", "CLAUDE_CODE_SESSION_ID": ""]) == nil)
        // An interactive session has no job directory and is still a caller.
        let interactive = SpawnLedger.Caller.of(environment: ["CLAUDE_CODE_SESSION_ID": "abc"])
        #expect(interactive == SpawnLedger.Caller(session: "abc"))
    }

    @Test func aCallerAnswersToAnyOfItsIdsAndToSixCharactersOfOne() throws {
        let caller = try #require(SpawnLedger.Caller.of(environment: Self.sessionEnvironment))
        #expect(caller.answers(to: "b87b7169"))
        #expect(caller.answers(to: "15a04072"))
        #expect(caller.answers(to: "session_01YYPbMRFLoY82q9xYDcFJjk"))
        #expect(!caller.answers(to: "b87"), "three characters is a guess, not an id")
        #expect(!caller.answers(to: ""))
        #expect(!caller.answers(to: "4ca3fb81"))
    }

    // MARK: the line

    /// lore's own example: the commander's lane, cut by ccc off a trunk
    /// that is not the default branch.
    private var lane: (asked: SpawnRequest, result: SpawnResult) {
        let asked = SpawnRequest(cwd: "/Users/x/code/attrition", prompt: "brief", name: "lane-4199",
                                 model: "claude-opus-5-5", effort: "high", worktree: "att-4199")
        let made = SpawnResult.MadeWorktree(path: "/Users/x/code/attrition/.claude/worktrees/att-4199",
                                            branch: "worktree-att-4199", base: "worktree-replan-pdb")
        let result = SpawnResult(ref: SessionRef(host: Host.localName, id: "4ca3fb81"), draft: false,
                                 cwd: made.path, said: "backgrounded · 4ca3fb81 · lane-4199", worktree: made)
        return (asked, result)
    }

    @Test func aLaneCarriesBothEndsAndTheBranchCCCCut() throws {
        let caller = SpawnLedger.Caller.of(environment: Self.sessionEnvironment)
        let entry = SpawnLedger.Entry.of(asked: lane.asked, result: lane.result, via: .cli, caller: caller,
                                         now: Date(timeIntervalSince1970: 1_794_610_800))
        #expect(entry.child == "4ca3fb81")
        #expect(entry.parent?.job == "b87b7169")
        #expect(entry.name == "lane-4199")
        #expect(entry.model == "claude-opus-5-5")
        #expect(entry.effort == "high")
        #expect(entry.kind == "spawn")
        #expect(entry.via == "cli")
        #expect(entry.worktree == "att-4199")
        #expect(entry.branch == "worktree-att-4199")
        #expect(entry.base == "worktree-replan-pdb")
        // The folder is where the session runs, not where it was asked from.
        #expect(entry.cwd == "/Users/x/code/attrition/.claude/worktrees/att-4199")
        // ISO 8601, UTC.
        #expect(entry.ts.hasSuffix("Z"))
        #expect(ISO8601DateFormatter().date(from: entry.ts) == Date(timeIntervalSince1970: 1_794_610_800))
    }

    /// The contract with a reader that is not Swift: every key on every
    /// line, and `parent` null — not absent — when nobody's session asked.
    @Test func everyKeyIsOnEveryLineAndATypedSpawnsParentIsNull() throws {
        let asked = SpawnRequest(cwd: "/Users/x/code/app")
        let result = SpawnResult(ref: SessionRef(host: Host.localName, id: "6b7e3fe6"), draft: true,
                                 cwd: "/Users/x/code/app", said: "backgrounded · 6b7e3fe6")
        let data = try SpawnLedger.line(.of(asked: asked, result: result, via: .cli, caller: nil))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("\n"), "one spawn is one line")
        #expect(text.contains("\"parent\":null"))
        #expect(text.contains("\"cwd\":\"/Users/x/code/app\""), "a path is written as a path, not as \\/")
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let keys = ["v", "ts", "kind", "via", "host", "child", "name", "model", "effort", "agent", "cwd",
                    "worktree", "branch", "base", "from", "replaced", "draft", "parent"]
        #expect(Set(object.keys) == Set(keys))
        #expect(object["v"] as? Int == SpawnLedger.version)
        #expect(object["draft"] as? Bool == true)
        #expect(object["name"] is NSNull)
        // A session's line carries all three of its ids, null where one is missing.
        let called = try SpawnLedger.line(.of(asked: asked, result: result, via: .cli,
                                              caller: SpawnLedger.Caller(job: "b87b7169")))
        let parent = try #require((try JSONSerialization.jsonObject(with: called) as? [String: Any])?["parent"] as? [String: Any])
        #expect(Set(parent.keys) == ["job", "session", "bridge"])
        #expect(parent["job"] as? String == "b87b7169")
        #expect(parent["bridge"] is NSNull)
    }

    @Test func aForkAndAReplacementSayWhatTheyCameFrom() {
        let sid = "1e7c5066-32da-4862-acef-0fc6b39f1bf9"
        let asked = SpawnRequest(cwd: "/x", name: "twin", from: sid)
        let result = SpawnResult(ref: SessionRef(host: "studio", id: "2f4c7814"), draft: true, cwd: "/x",
                                 said: "", from: sid)
        let entry = SpawnLedger.Entry.of(asked: asked, result: result, via: .app, caller: nil, replaced: "0a1b2c3d")
        #expect(entry.kind == "fork")
        #expect(entry.from == sid)
        #expect(entry.replaced == "0a1b2c3d")
        #expect(entry.host == "studio")
        #expect(entry.via == "app")
        // The harness cut nothing ccc saw: no branch is claimed.
        let harness = SpawnLedger.Entry.of(asked: SpawnRequest(cwd: "/x", worktree: ""), result: result, via: .cli, caller: nil)
        #expect(harness.worktree == "")
        #expect(harness.branch == nil && harness.base == nil)
    }

    // MARK: the file

    @Test func linesAppendAndReadBackAndABrokenOneCostsOnlyItself() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        // The directory does not exist yet: the first spawn on a Mac makes it.
        let ledger = SpawnLedger(path: dir.appending(path: "ccc/spawns.jsonl").path)
        #expect(ledger.read() == SpawnLedger.Reading(entries: [], skipped: 0))
        let caller = SpawnLedger.Caller.of(environment: Self.sessionEnvironment)
        let first = SpawnLedger.Entry.of(asked: lane.asked, result: lane.result, via: .cli, caller: caller)
        let second = SpawnLedger.Entry.of(asked: SpawnRequest(cwd: "/x"), result: lane.result, via: .app, caller: nil)
        try ledger.append(first)
        try ledger.append(second)
        #expect(ledger.read() == SpawnLedger.Reading(entries: [first, second], skipped: 0))
        // A torn line, and a record from a later ccc with a kind and a key
        // this build has never heard of.
        let handle = try FileHandle(forWritingTo: URL(filePath: ledger.path))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"child\":\"trunc\n".utf8))
        try handle.write(contentsOf: Data("{\"child\":\"9f8e7d6c\",\"kind\":\"respawn\",\"later\":{\"a\":1}}\n".utf8))
        try handle.close()
        let reading = ledger.read()
        #expect(reading.skipped == 1)
        #expect(reading.entries.count == 3)
        #expect(reading.entries.last?.kind == "respawn")
        #expect(reading.entries.last?.parent == nil)
    }

    /// A commander fans lanes out in parallel; each must get a whole line.
    @Test func spawnsLandingTogetherEachGetAWholeLine() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ledger = SpawnLedger(path: dir.appending(path: "spawns.jsonl").path)
        let (asked, result) = lane
        await withTaskGroup(of: Void.self) { group in
            for n in 0..<24 {
                group.addTask {
                    var one = result
                    one.ref = SessionRef(host: Host.localName, id: String(format: "%08x", n))
                    try? ledger.append(.of(asked: asked, result: one, via: .cli, caller: nil))
                }
            }
        }
        let reading = ledger.read()
        #expect(reading.skipped == 0)
        #expect(Set(reading.entries.map(\.child)).count == 24)
    }

    // MARK: the spawn itself

    private func fakeClaude(in dir: URL) throws -> ClaudeCLI {
        let claude = dir.appending(path: "claude").path
        let body = "#!/bin/sh\nprintf '%s' '\(SpawnTests.promptedAnswer)'\n"
        try Data(body.utf8).write(to: URL(filePath: claude))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude)
        return ClaudeCLI(executable: claude, host: .local)
    }

    /// The whole road, with the harness stubbed by its own recorded
    /// answer: the line is written by the spawn, not by whoever prints
    /// the result.
    @Test func aSpawnWritesItsOwnLine() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ledger = SpawnLedger(path: dir.appending(path: "spawns.jsonl").path)
        let caller = SpawnLedger.Caller.of(environment: Self.sessionEnvironment)
        let request = SpawnRequest(cwd: dir.path, prompt: "fix it", name: "ccc-v5-probe", model: "haiku", effort: "low")
        let result = try await fakeClaude(in: dir).spawn(request, caller: caller, ledger: ledger)
        #expect(result.ref.id == "2f4c7814")
        #expect(result.unledgered == nil)
        let entries = ledger.read().entries
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.child == "2f4c7814")
        #expect(entry.parent == caller)
        #expect(entry.name == "ccc-v5-probe")
        #expect(entry.model == "haiku")
        #expect(entry.cwd == dir.path)
        #expect(entry.via == "cli")
        #expect(!entry.draft)
    }

    /// The session exists once the harness has answered. A ledger that
    /// cannot be written is a sentence in the answer, never a failed spawn.
    @Test func aLedgerThatCannotBeWrittenNeverCostsTheSpawn() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A file where the ledger's directory should be.
        let blocker = dir.appending(path: "not-a-directory")
        try Data().write(to: blocker)
        let ledger = SpawnLedger(path: blocker.appending(path: "spawns.jsonl").path)
        let result = try await fakeClaude(in: dir).spawn(SpawnRequest(cwd: dir.path, prompt: "fix it"), caller: nil, ledger: ledger)
        #expect(result.ref.id == "2f4c7814")
        #expect(result.unledgered != nil)
        // And `ledger: nil` writes nothing and says nothing.
        let quiet = try await fakeClaude(in: dir).spawn(SpawnRequest(cwd: dir.path, prompt: "fix it"), caller: nil, ledger: nil)
        #expect(quiet.unledgered == nil)
    }

    // MARK: the words

    /// The path and the three variables are what lore keys on; a string no
    /// test reads is a string nothing keeps true.
    @Test func theHelpNamesThePathAndTheVariablesTheParentIsReadFrom() throws {
        let spawns = try #require(CommandManifest.verb(named: "spawns"))
        let text = CommandManifest.help(for: spawns)
        #expect(text.contains("Application Support/ccc/spawns.jsonl"))
        #expect(text.contains("CCC_SPAWN_LEDGER"))
        for variable in SpawnLedger.Caller.variables {
            #expect(text.contains(variable), "`ccc spawns --help` does not name \(variable)")
        }
        #expect(SpawnLedger(path: "/x").path == "/x")
        #expect(SpawnLedger.defaultPath.hasSuffix("/ccc/spawns.jsonl") || ProcessInfo.processInfo.environment["CCC_SPAWN_LEDGER"] != nil)
        let spawn = try #require(CommandManifest.verb(named: "spawn"))
        #expect(CommandManifest.help(for: spawn).contains("`ccc spawns`"))
        #expect(spawn.json?.contains("unledgered") == true)
    }
}
