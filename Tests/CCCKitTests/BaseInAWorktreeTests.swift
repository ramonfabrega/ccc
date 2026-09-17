import Foundation
import Testing

@testable import CCCKit

/// **The base branch lives in a worktree** (2026-09-17): the shape
/// attrition's worker loop makes, where `merge` and `pull` refused.
///
/// Its integration branch `worktree-replan-pdb` is permanently checked
/// out in `.claude/worktrees/replan-pdb` — every landing goes there — and
/// the main checkout stays on `main`, which only ever gets fast-forwarded
/// by hand. Both verbs ran `git -C <main checkout>` and refused unless
/// HEAD was the base, so every `ccc merge` on that loop answered
/// "/…/attrition is on main, not worktree-replan-pdb; refusing to merge"
/// and the commander hand-rolled `git merge --no-ff` instead — losing the
/// base-moved check, the dirty refusal and the conflict back-out, which
/// is the whole reason to call the verb. Reported by that repo's
/// commander after four of them.
///
/// The repository here is that repository's shape, made small: a bare
/// origin, a main checkout on `main`, the base in one worktree, a worker
/// off the base in another with `branch.<w>.ccc-base` recorded, and a
/// second clone standing in for the other Mac.
@Suite(.serialized) struct BaseInAWorktreeTests {
    private struct Shape {
        let root: URL          // the main checkout, on `main`
        let base: URL          // .claude/worktrees/integration, on `worktree-integration`
        let worker: URL        // .claude/worktrees/w, on `worktree-w`, base recorded
        let plain: URL         // .claude/worktrees/m, on `worktree-m`, no recorded base
        let other: URL         // a clone: the other Mac
        let git: (String, URL) throws -> String

        func commit(_ name: String, in dir: URL) throws {
            try "x\n".write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
            _ = try git("add \(name)", dir)
            _ = try git("commit -q --no-verify -m \(name)", dir)
        }

        func head(_ branch: String) throws -> String { try git("rev-parse \(branch)", root) }
    }

    private func withShape(_ body: (Shape) throws -> Void) throws {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-basewt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let origin = dir.appending(path: "origin.git"), root = dir.appending(path: "repo")
        let other = dir.appending(path: "other")
        func git(_ line: String, _ at: URL) throws -> String {
            try Git.run(WorktreeProbe.defaultGit, ["-C", at.path] + line.split(separator: " ").map(String.init)).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = try Git.run(WorktreeProbe.defaultGit, ["init", "-q", "--bare", "-b", "main", origin.path])
        _ = try Git.run(WorktreeProbe.defaultGit, ["init", "-q", "-b", "main", root.path])
        _ = try git("config user.email t@example.com", root)
        _ = try git("config user.name t", root)
        try "one\n".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        _ = try git("add a.txt", root)
        _ = try git("commit -q --no-verify -m first", root)
        _ = try git("remote add origin \(origin.path)", root)
        _ = try git("push -q -u origin main", root)
        try FileManager.default.createDirectory(at: root.appending(path: ".claude/worktrees"),
                                               withIntermediateDirectories: true)
        // The integration branch, in its own worktree, on origin.
        let base = root.appending(path: ".claude/worktrees/integration")
        _ = try git("worktree add -q -b worktree-integration \(base.path) main", root)
        try "two\n".write(to: base.appending(path: "b.txt"), atomically: true, encoding: .utf8)
        _ = try git("add b.txt", base)
        _ = try git("commit -q --no-verify -m integration", base)
        _ = try git("push -q -u origin worktree-integration", root)
        // A worker off it, with the base recorded the way `ccc spawn --base` does.
        let worker = root.appending(path: ".claude/worktrees/w")
        _ = try git("worktree add -q -b worktree-w \(worker.path) worktree-integration", root)
        try WorktreeProbe.recordBase("worktree-integration", for: "worktree-w", repo: root.path)
        // And an ordinary worker off the default branch, to prove nothing moved for it.
        let plain = root.appending(path: ".claude/worktrees/m")
        _ = try git("worktree add -q -b worktree-m \(plain.path) main", root)
        _ = try Git.run(WorktreeProbe.defaultGit, ["clone", "-q", origin.path, other.path])
        _ = try git("config user.email o@example.com", other)
        _ = try git("config user.name o", other)
        try body(Shape(root: root, base: base, worker: worker, plain: plain, other: other, git: git))
    }

    @Test func theTreeHoldingABranchIsFound() throws {
        try withShape { s in
            let held = try #require(WorktreeProbe.checkoutHolding("worktree-integration", repo: s.root.path))
            #expect(WorktreeProbe.samePath(held, s.base.path))
            #expect(WorktreeProbe.inRepoPath(held, repo: s.root.path) == ".claude/worktrees/integration")
            // The main checkout answers for its own branch, and a branch no
            // tree has checked out answers nil rather than a guess.
            let main = try #require(WorktreeProbe.checkoutHolding("main", repo: s.root.path))
            #expect(WorktreeProbe.samePath(main, s.root.path))
            #expect(WorktreeProbe.checkoutHolding("no-such-branch", repo: s.root.path) == nil)
        }
    }

    @Test func theRecordedBaseIsWhatTheWorkerIsMeasuredAgainst() throws {
        try withShape { s in
            let info = try #require(WorktreeProbe().fresh(forCwd: s.worker.path))
            #expect(info.base == "worktree-integration")
            #expect(info.baseRecorded == true)
            // The plain worker's base is the default branch, as ever.
            #expect(WorktreeProbe().fresh(forCwd: s.plain.path)?.base == "main")
        }
    }

    @Test func aFastForwardLandsInTheTreeHoldingTheBase() throws {
        try withShape { s in
            try s.commit("w.txt", in: s.worker)
            let before = try s.head("main")
            let info = try #require(WorktreeProbe().fresh(forCwd: s.worker.path))
            let outcome = GitMerge.perform(.ffOnly, on: info)
            #expect(outcome.merged, "\(outcome.said)")
            // The sentence names the tree it wrote to: nothing silent.
            #expect(outcome.said.contains("worktree-w → worktree-integration in .claude/worktrees/integration"))
            #expect(try s.head("worktree-integration") == (try s.head("worktree-w")))
            #expect(try s.head("main") == before, "the default branch is not this loop's business")
            // And the worktree that holds the base has the file, checked out.
            #expect(FileManager.default.fileExists(atPath: s.base.appending(path: "w.txt").path))
        }
    }

    @Test func aMergeCommitAndASquashLandThereToo() throws {
        try withShape { s in
            try s.commit("w.txt", in: s.worker)
            try s.commit("i.txt", in: s.base)   // the base moved: no fast-forward
            let probe = WorktreeProbe()
            let ff = GitMerge.perform(.ffOnly, on: try #require(probe.fresh(forCwd: s.worker.path)))
            #expect(!ff.merged && ff.said.contains("a fast-forward is not possible"))
            let merged = GitMerge.perform(.noFF, on: try #require(probe.fresh(forCwd: s.worker.path)))
            #expect(merged.merged, "\(merged.said)")
            #expect(merged.said.contains("in .claude/worktrees/integration"))
            #expect(try s.git("log --format=%s -1", s.base) == "Merge worktree-w (1 commit)")
            // And the third strategy, on one more commit of the worker's.
            try s.commit("w2.txt", in: s.worker)
            let squashed = GitMerge.perform(.squash, on: try #require(probe.fresh(forCwd: s.worker.path)))
            #expect(squashed.merged, "\(squashed.said)")
            #expect(squashed.said.contains("in .claude/worktrees/integration"))
            #expect(try s.git("log --format=%s -1", s.base) == "Squash worktree-w (1 commit)")
            #expect(try s.git("status --porcelain", s.base).isEmpty)
        }
    }

    @Test func aDirtyTreeHoldingTheBaseIsRefusedAndNamed() throws {
        try withShape { s in
            try s.commit("w.txt", in: s.worker)
            try "dirty\n".write(to: s.base.appending(path: "b.txt"), atomically: true, encoding: .utf8)
            let info = try #require(WorktreeProbe().fresh(forCwd: s.worker.path))
            let outcome = GitMerge.perform(.ffOnly, on: info)
            #expect(!outcome.merged)
            // The refusal is about the tree the merge would have run in —
            // which is the sentence the commander needed and never got.
            #expect(outcome.said.contains(".claude/worktrees/integration"))
            #expect(outcome.said.contains("1 uncommitted change"))
            #expect(try s.head("worktree-integration") != (try s.head("worktree-w")))
        }
    }

    @Test func aConflictBacksOutOfThatTreeToo() throws {
        try withShape { s in
            try "mine\n".write(to: s.worker.appending(path: "c.txt"), atomically: true, encoding: .utf8)
            _ = try s.git("add c.txt", s.worker)
            _ = try s.git("commit -q --no-verify -m mine", s.worker)
            try "theirs\n".write(to: s.base.appending(path: "c.txt"), atomically: true, encoding: .utf8)
            _ = try s.git("add c.txt", s.base)
            _ = try s.git("commit -q --no-verify -m theirs", s.base)
            let tip = try s.head("worktree-integration")
            let outcome = GitMerge.perform(.noFF, on: try #require(WorktreeProbe().fresh(forCwd: s.worker.path)))
            #expect(!outcome.merged)
            #expect(outcome.said.contains("conflicts in c.txt"))
            #expect(try s.head("worktree-integration") == tip, "backed out where it ran")
            #expect(try s.git("status --porcelain", s.base).isEmpty, "and left that tree clean")
        }
    }

    @Test func anOrdinaryBaseStillLandsInTheMainCheckoutAndSaysNothingAboutIt() throws {
        try withShape { s in
            try s.commit("m.txt", in: s.plain)
            let outcome = GitMerge.perform(.ffOnly, on: try #require(WorktreeProbe().fresh(forCwd: s.plain.path)))
            #expect(outcome.merged, "\(outcome.said)")
            #expect(outcome.said.contains("worktree-m → main ("), "no location where there is nothing to say")
            #expect(!outcome.said.contains(".claude/worktrees"))
        }
    }

    @Test func pullFastForwardsTheBaseWhereItIsCheckedOut() throws {
        try withShape { s in
            // The other Mac lands on the integration branch and pushes.
            _ = try s.git("checkout -q -b worktree-integration origin/worktree-integration", s.other)
            try s.commit("theirs.txt", in: s.other)
            _ = try s.git("push -q origin worktree-integration", s.other)
            _ = try s.git("fetch -q origin", s.root)
            let probe = WorktreeProbe()
            let info = try #require(probe.fresh(forCwd: s.worker.path))
            #expect(info.baseUnpulled == 1 && info.baseUnpushed == 0)
            let outcome = GitPull.perform(on: info)
            #expect(outcome.merged, "\(outcome.said)")
            #expect(outcome.said.contains("pulled origin/worktree-integration → worktree-integration in .claude/worktrees/integration"))
            #expect(try s.head("worktree-integration") == (try s.git("rev-parse origin/worktree-integration", s.root)))
            #expect(FileManager.default.fileExists(atPath: s.base.appending(path: "theirs.txt").path),
                    "the tree that holds the base has the other Mac's file")
        }
    }

    @Test func pushBaseSendsTheRecordedBaseNotTheDefaultBranch() throws {
        try withShape { s in
            // A landing on the integration branch that origin has not seen.
            try s.commit("landed.txt", in: s.base)
            let info = try #require(WorktreeProbe().fresh(forCwd: s.worker.path))
            #expect(info.baseUnpushed == 1)
            let outcome = GitPush.perform(.base, on: info)
            #expect(outcome.merged, "\(outcome.said)")
            #expect(outcome.said.contains("pushed worktree-integration → origin"))
            #expect(try s.git("rev-parse origin/worktree-integration", s.root) == (try s.head("worktree-integration")))
            // The default branch was never the target — the help said it was
            // for eleven releases and the code never did (2026-09-17).
            #expect(try s.git("rev-parse origin/main", s.root) == (try s.head("main")))
        }
    }
}
