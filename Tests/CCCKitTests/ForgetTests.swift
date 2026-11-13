import Foundation
import Testing

@testable import CCCKit

/// `ccc forget`: `claude rm` only when it would take the row and nothing
/// else. The cases are the ones measured on owned fixtures 2026-10-07
/// (`docs/EVIDENCE.md` "forget — what `claude rm` takes").
@Suite struct ForgetTests {
    static func row(state: Session.State?, status: Session.Status? = nil, pid: Int32? = nil,
                    kind: Session.Kind = .background) -> Session {
        Session(id: "98d6e15e", cwd: "/r/.claude/worktrees/shared", kind: kind, startedAt: .now,
                state: state, status: status, pid: pid, name: "commander-old-2")
    }

    /// The case it was built for: a stopped row on a shared worktree it
    /// did not cut. `claude rm` took the row and left the tree.
    @Test func aFinishedRowOnASharedTreeIsForgotten() {
        for state in [Session.State.done, .stopped, .failed] {
            #expect(ForgetGuard.refusal(Self.row(state: state), harnessTree: nil, cutTree: nil) == nil)
        }
    }

    /// `done` ends a turn, not a session: the live steer read `done/busy`.
    @Test func doneWithAProcessIsRefused() throws {
        let busy = try #require(ForgetGuard.refusal(Self.row(state: .done, status: .busy, pid: 4242),
                                                    harnessTree: nil, cutTree: nil))
        #expect(busy.contains("still has a process (pid 4242)"))
        #expect(busy.contains("ccc stop 98d6e15e"))
        // Either half alone is still a session that is there.
        #expect(ForgetGuard.refusal(Self.row(state: .done, status: .idle), harnessTree: nil, cutTree: nil) != nil)
        #expect(ForgetGuard.refusal(Self.row(state: .stopped, pid: 1), harnessTree: nil, cutTree: nil) != nil)
    }

    /// `ccc stop` answers when the process is off the roster, which is
    /// what makes `ccc forget` straight after it not a race (attrition,
    /// 2026-11-13: forget refused "still has a process" on a row `stop`
    /// had just answered for). The wait is over the same two fields the
    /// refusal above reads.
    @Test func stopWaitsForTheProcessToLeaveTheRoster() async {
        final class Reads: @unchecked Sendable { var n = 0 }
        let reads = Reads()
        let gone = await ClaudeCLI.awaitExit(of: "98d6e15e", patience: .seconds(5), every: .milliseconds(5)) {
            reads.n += 1
            return [Self.row(state: .stopped, pid: reads.n < 3 ? 4242 : nil)]
        }
        #expect(gone == nil)
        #expect(reads.n == 3)

        // Gone on the first read costs one read; so does a row the roster
        // has already dropped, and a roster that does not answer.
        for roster in [[Self.row(state: .done)], [], nil] as [[Session]?] {
            let reads = Reads()
            #expect(await ClaudeCLI.awaitExit(of: "98d6e15e", patience: .seconds(5), every: .milliseconds(5)) {
                reads.n += 1
                return roster
            } == nil)
            #expect(reads.n == 1)
        }

        // A process that outlives the patience is handed back, to be named.
        let lingering = await ClaudeCLI.awaitExit(of: "commander-old-2", patience: .milliseconds(30), every: .milliseconds(5)) {
            [Self.row(state: .done, status: .busy, pid: 4242)]
        }
        #expect(lingering?.pid == 4242)
    }

    @Test func aLiveStateIsRefused() {
        for state in [Session.State.working, .blocked] {
            let said = ForgetGuard.refusal(Self.row(state: state), harnessTree: nil, cutTree: nil)
            #expect(said?.contains(state.rawValue) == true)
        }
        #expect(ForgetGuard.refusal(Self.row(state: nil), harnessTree: nil, cutTree: nil) != nil,
                "a state this build cannot read is never finished")
    }

    /// The `--worktree` fixture: its job file named the tree and `rm` took it.
    @Test func aTreeTheHarnessCutIsRmsNotForgets() throws {
        let said = try #require(ForgetGuard.refusal(Self.row(state: .done), harnessTree: "/r/.claude/worktrees/fxcut",
                                                    cutTree: nil))
        #expect(said.contains("/r/.claude/worktrees/fxcut"))
        #expect(said.contains("ccc rm 98d6e15e"))
    }

    @Test func aTreeCccCutIsRmsNotForgets() throws {
        let said = try #require(ForgetGuard.refusal(Self.row(state: .stopped), harnessTree: nil, cutTree: "/r/wt"))
        #expect(said.contains("ccc cut"))
    }

    @Test func anInteractiveSessionHasNoRowToDrop() {
        #expect(ForgetGuard.refusal(Self.row(state: .done, kind: .interactive), harnessTree: nil, cutTree: nil)?
            .contains("interactive") == true)
    }

    /// The job-file read: `worktreePath` or nothing, leniently.
    @Test func theJobFileNamesTheHarnessTree() throws {
        let jobs = FileManager.default.temporaryDirectory.appending(path: "forget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: jobs) }
        func write(_ id: String, _ body: String) throws {
            let dir = jobs.appending(path: id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(body.utf8).write(to: dir.appending(path: "state.json"))
        }
        try write("cut", #"{"worktreePath":"/r/.claude/worktrees/fxcut","worktreeBranch":"worktree-fxcut"}"#)
        try write("cwd", #"{"cwd":"/r/.claude/worktrees/shared","state":"stopped"}"#)
        try write("odd", #"{"worktreePath":42}"#)
        try write("blank", #"{"worktreePath":"  "}"#)
        #expect(ForgetGuard.harnessWorktree(forJob: "cut", jobsDirectory: jobs) == "/r/.claude/worktrees/fxcut")
        #expect(ForgetGuard.harnessWorktree(forJob: "cwd", jobsDirectory: jobs) == nil)
        #expect(ForgetGuard.harnessWorktree(forJob: "odd", jobsDirectory: jobs) == nil)
        #expect(ForgetGuard.harnessWorktree(forJob: "blank", jobsDirectory: jobs) == nil)
        #expect(ForgetGuard.harnessWorktree(forJob: "missing", jobsDirectory: jobs) == nil)
    }

    @Test func theHelpSaysWhatStays() throws {
        let verb = try #require(CommandManifest.verb(named: "forget"))
        let text = CommandManifest.help(for: verb)
        #expect(text.contains("KEEP ITS WORKTREE AND BRANCH"))
        #expect(text.contains("ccc stop"))
        #expect(text.contains("ccc rm"))
        let clear = try #require(CommandManifest.verb(named: "clear"))
        #expect(CommandManifest.help(for: clear).contains("Any session may clear another"),
                "measured 2026-10-07; attrition's hand-off depends on it")
    }
}
