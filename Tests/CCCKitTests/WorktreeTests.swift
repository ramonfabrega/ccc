import Foundation
import Testing

@testable import CCCKit

/// The worktree reading (v6) and the merge that acts on it, on real git
/// repositories made in a temp folder: the harness's own layout (a main
/// checkout, `.claude/worktrees/<name>` on `worktree-<name>`), so the
/// files the probe reads are the files git writes.
@Suite(.serialized) struct WorktreeTests {
    private struct Repo {
        let root: URL
        let worktree: URL
        var wt: String { worktree.path }

        func git(_ args: String..., in dir: URL? = nil) throws -> String {
            try Git.run(WorktreeProbe.defaultGit, ["-C", (dir ?? root).path] + args).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// One commit writing `text` to `file`, in the main checkout or the worktree.
        func commit(_ file: String, _ text: String, message: String, worktree: Bool = false) throws {
            let dir = worktree ? self.worktree : root
            try text.write(to: dir.appending(path: file), atomically: true, encoding: .utf8)
            _ = try git("add", file, in: dir)
            _ = try git("commit", "-q", "--no-verify", "-m", message, in: dir)
        }
    }

    private func withRepo(_ body: (Repo) throws -> Void) throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = Repo(root: root, worktree: root.appending(path: ".claude/worktrees/t"))
        _ = try repo.git("init", "-q", "-b", "master")
        _ = try repo.git("config", "user.email", "t@example.com")
        _ = try repo.git("config", "user.name", "t")
        try repo.commit("a.txt", "one\n", message: "first")
        try FileManager.default.createDirectory(at: root.appending(path: ".claude"), withIntermediateDirectories: true)
        _ = try repo.git("worktree", "add", "-q", "-b", "worktree-t", repo.wt, "master")
        try body(repo)
    }

    @Test func aPlainFolderIsNotAWorktree() throws {
        try withRepo { repo in
            #expect(WorktreeProbe.layout(of: repo.root.path) == nil)
            #expect(WorktreeProbe().info(forCwd: repo.root.path) == nil)
            #expect(WorktreeProbe().info(forCwd: NSTemporaryDirectory()) == nil)
        }
    }

    @Test func theLayoutComesFromGitsOwnFiles() throws {
        try withRepo { repo in
            let layout = try #require(WorktreeProbe.layout(of: repo.wt))
            #expect(layout.branch == "worktree-t")
            #expect(layout.repo == repo.root.standardizedFileURL.path)
            #expect(layout.commonDir == repo.root.standardizedFileURL.appending(path: ".git").path)
            // A session deep in the tree resolves to the same worktree.
            let deep = repo.worktree.appending(path: "Sources/x")
            try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
            #expect(WorktreeProbe.layout(of: deep.path)?.branch == "worktree-t")
            #expect(WorktreeProbe.defaultBranch(commonDir: layout.commonDir) == "master")
        }
    }

    @Test func aheadAndBehindFollowTheCommits() throws {
        try withRepo { repo in
            let probe = WorktreeProbe()
            // Level: a fresh worktree has nothing to land — and the row
            // still says which branch it is on.
            let level = try #require(probe.info(forCwd: repo.wt))
            var expected = WorktreeInfo(branch: "worktree-t", base: "master", ahead: 0, behind: 0,
                                        repo: repo.root.standardizedFileURL.path)
            expected.baseRecorded = false   // the default branch, nothing recorded (item 18)
            #expect(level == expected)
            #expect(!level.hasWork && !level.canFastForward)
            #expect(level.summary == "worktree-t level")
            try repo.commit("b.txt", "two\n", message: "wt one", worktree: true)
            try repo.commit("c.txt", "three\n", message: "wt two", worktree: true)
            let ahead = try #require(probe.info(forCwd: repo.wt))
            #expect(ahead.ahead == 2 && ahead.behind == 0 && ahead.canFastForward)
            #expect(ahead.summary == "worktree-t ↑2")
            try repo.commit("d.txt", "four\n", message: "master moved")
            let diverged = try #require(probe.info(forCwd: repo.wt))
            #expect(diverged.ahead == 2 && diverged.behind == 1 && !diverged.canFastForward && diverged.hasWork)
            #expect(diverged.summary == "worktree-t ↑2 ↓1")
        }
    }

    @Test func theCacheSpawnsGitOnlyWhenAShaMoves() throws {
        try withRepo { repo in
            let probe = WorktreeProbe()
            _ = probe.info(forCwd: repo.wt)
            _ = probe.info(forCwd: repo.wt)
            _ = probe.info(forCwd: repo.wt)
            #expect(probe.spawns == 1)
            try repo.commit("b.txt", "two\n", message: "wt one", worktree: true)
            _ = probe.info(forCwd: repo.wt)
            _ = probe.info(forCwd: repo.wt)
            #expect(probe.spawns == 2)
            // `fresh` never trusts the cache.
            _ = probe.fresh(forCwd: repo.wt)
            #expect(probe.spawns == 3)
        }
    }

    @Test func packedRefsResolveToo() throws {
        try withRepo { repo in
            try repo.commit("b.txt", "two\n", message: "wt one", worktree: true)
            _ = try repo.git("pack-refs", "--all")
            let common = repo.root.standardizedFileURL.appending(path: ".git").path
            #expect(WorktreeProbe.sha(of: "master", commonDir: common)?.count == 40)
            #expect(WorktreeProbe.sha(of: "worktree-t", commonDir: common)?.count == 40)
            #expect(WorktreeProbe().info(forCwd: repo.wt)?.ahead == 1)
        }
    }

    @Test func fastForwardLandsAndLeavesTheBranchesLevel() throws {
        try withRepo { repo in
            try repo.commit("b.txt", "two\n", message: "wt one", worktree: true)
            let probe = WorktreeProbe()
            let info = try #require(probe.fresh(forCwd: repo.wt))
            let outcome = GitMerge.perform(.ffOnly, on: info)
            #expect(outcome.merged, "\(outcome.said)")
            #expect(outcome.said.hasPrefix("fast-forwarded worktree-t → master (1 commit"))
            #expect(try repo.git("rev-parse", "master") == repo.git("rev-parse", "worktree-t"))
            #expect(probe.fresh(forCwd: repo.wt)?.summary == "worktree-t level")
            // And nothing to do the second time.
            let again = GitMerge.perform(.ffOnly, on: try #require(probe.fresh(forCwd: repo.wt)))
            #expect(!again.merged && again.said.hasPrefix("nothing to merge"))
        }
    }

    @Test func fastForwardRefusesWhenMasterMoved() throws {
        try withRepo { repo in
            try repo.commit("b.txt", "two\n", message: "wt one", worktree: true)
            try repo.commit("d.txt", "four\n", message: "master moved")
            let before = try repo.git("rev-parse", "master")
            let info = try #require(WorktreeProbe().fresh(forCwd: repo.wt))
            let outcome = GitMerge.perform(.ffOnly, on: info)
            #expect(!outcome.merged)
            #expect(outcome.said.contains("master has moved 1 commit past worktree-t"))
            #expect(try repo.git("rev-parse", "master") == before)
        }
    }

    @Test func mergeCommitWhenDiverged() throws {
        try withRepo { repo in
            try repo.commit("b.txt", "two\n", message: "wt one", worktree: true)
            try repo.commit("d.txt", "four\n", message: "master moved")
            let info = try #require(WorktreeProbe().fresh(forCwd: repo.wt))
            let outcome = GitMerge.perform(.noFF, on: info)
            #expect(outcome.merged, "\(outcome.said)")
            #expect(outcome.said.hasPrefix("merged worktree-t → master (1 commit, merge commit"))
            #expect(try repo.git("log", "-1", "--format=%s") == "Merge worktree-t (1 commit)")
            #expect(try repo.git("rev-list", "--parents", "-1", "HEAD").split(separator: " ").count == 3)
            #expect(FileManager.default.fileExists(atPath: repo.root.appending(path: "b.txt").path))
            // Repeatable: the merge base moved with the merge.
            #expect(WorktreeProbe().fresh(forCwd: repo.wt)?.ahead == 0)
        }
    }

    @Test func squashIsOneCommitCarryingTheSubjects() throws {
        try withRepo { repo in
            try repo.commit("b.txt", "two\n", message: "wt one", worktree: true)
            try repo.commit("c.txt", "three\n", message: "wt two", worktree: true)
            let info = try #require(WorktreeProbe().fresh(forCwd: repo.wt))
            let outcome = GitMerge.perform(.squash, on: info)
            #expect(outcome.merged, "\(outcome.said)")
            #expect(outcome.said.hasPrefix("squashed worktree-t → master (2 commits →"))
            #expect(outcome.said.contains("a second squash would re-apply"))
            let body = try repo.git("log", "-1", "--format=%B")
            #expect(body.hasPrefix("Squash worktree-t (2 commits)"))
            #expect(body.contains("- wt two") && body.contains("- wt one"))
            #expect(try repo.git("rev-list", "--count", "master") == "2")
            #expect(try repo.git("status", "--porcelain", "--untracked-files=no") == "")
        }
    }

    @Test func aDirtyCheckoutRefuses() throws {
        try withRepo { repo in
            try repo.commit("b.txt", "two\n", message: "wt one", worktree: true)
            try "changed\n".write(to: repo.root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
            let before = try repo.git("rev-parse", "master")
            let info = try #require(WorktreeProbe().fresh(forCwd: repo.wt))
            for strategy in MergeStrategy.allCases {
                let outcome = GitMerge.perform(strategy, on: info)
                // Named, not just counted: the commander that meets this
                // refusal is asking whether the dirt is its own test run.
                #expect(!outcome.merged && outcome.said.contains("1 uncommitted change (a.txt)"), "\(outcome.said)")
            }
            #expect(try repo.git("rev-parse", "master") == before)
            #expect(try repo.git("status", "--porcelain", "--untracked-files=no").contains("M a.txt"))
        }
    }

    /// Four paths then a count, and a rename reads as the path on disk:
    /// the refusal has to fit one line in a banner and a `--json` field.
    @Test func manyDirtyFilesAreCutToFourAndCounted() throws {
        try withRepo { repo in
            for name in ["d.txt", "e.txt", "f.txt", "g.txt", "h.txt"] {
                try repo.commit(name, "x\n", message: "master \(name)")
            }
            try repo.commit("b.txt", "two\n", message: "wt one", worktree: true)
            let info = try #require(WorktreeProbe().fresh(forCwd: repo.wt))
            let before = try repo.git("rev-parse", "master")
            // A rename reads as the path that is now on disk, not as
            // git's `old -> new` pair.
            _ = try repo.git("mv", "d.txt", "moved.txt")
            let renamed = GitMerge.perform(.noFF, on: info).said
            #expect(renamed.contains("1 uncommitted change (moved.txt)"), "\(renamed)")
            #expect(!renamed.contains("d.txt -> "), "\(renamed)")
            for name in ["e.txt", "f.txt", "g.txt", "h.txt"] {
                try "changed\n".write(to: repo.root.appending(path: name), atomically: true, encoding: .utf8)
            }
            let said = GitMerge.perform(.noFF, on: info).said
            #expect(said.contains("5 uncommitted changes ("), "\(said)")
            #expect(said.contains("(+1)"), "\(said)")
            #expect(said.split(separator: ", ").count == 4, "four paths then a count: \(said)")
            #expect(try repo.git("rev-parse", "master") == before, "refused before it touched master")
        }
    }

    @Test func aCheckoutOffMasterRefuses() throws {
        try withRepo { repo in
            try repo.commit("b.txt", "two\n", message: "wt one", worktree: true)
            _ = try repo.git("checkout", "-q", "-b", "elsewhere")
            let info = try #require(WorktreeProbe().fresh(forCwd: repo.wt))
            let outcome = GitMerge.perform(.ffOnly, on: info)
            #expect(!outcome.merged && outcome.said.contains("is on elsewhere, not master"))
        }
    }

    @Test func aConflictBacksOutCleanly() throws {
        try withRepo { repo in
            try repo.commit("a.txt", "theirs\n", message: "wt edit", worktree: true)
            try repo.commit("a.txt", "ours\n", message: "master edit")
            let before = try repo.git("rev-parse", "master")
            // The fourth thing a back-out owes, and the one nothing read
            // until it was promised to a live loop: the worker's side is
            // not a party to the merge, so its branch keeps every commit
            // and its tree stays clean however the base's side failed.
            let worker = try repo.git("rev-parse", "worktree-t")
            let info = try #require(WorktreeProbe().fresh(forCwd: repo.wt))
            for strategy in [MergeStrategy.noFF, .squash] {
                let outcome = GitMerge.perform(strategy, on: info)
                #expect(!outcome.merged, "\(outcome.said)")
                // The whole line, not a substring: a live collision proved
                // the update twin exact (2026-09-17), and this is the
                // sentence the reporter will send off the first real merge
                // one — so it is compared against a test, not a memory.
                let verb = strategy == .noFF ? "merge" : "squash"
                #expect(outcome.said == "\(verb) worktree-t → master conflicts in a.txt; backed out, master untouched",
                        "\(outcome.said)")
                #expect(try repo.git("rev-parse", "master") == before)
                #expect(try repo.git("status", "--porcelain", "--untracked-files=no") == "")
                #expect(try String(contentsOf: repo.root.appending(path: "a.txt"), encoding: .utf8) == "ours\n")
                #expect(try repo.git("rev-parse", "worktree-t") == worker, "the worker keeps its commits")
                #expect(try repo.git("status", "--porcelain", "--untracked-files=no", in: repo.worktree) == "",
                        "and its tree is untouched")
            }
        }
    }

    /// The other four-then-count cut, in the back-out's own sentence
    /// rather than the dirty refusal's: read by nothing until a live loop
    /// was about to meet a collision wider than one file. Both verbs that
    /// back out say it, out of one helper, so both are checked here.
    @Test func aWideConflictNamesFourFilesThenACount() throws {
        try withRepo { repo in
            let files = ["a.txt", "p.txt", "q.txt", "r.txt", "s.txt", "t.txt"]
            for name in files where name != "a.txt" {
                try repo.commit(name, "base\n", message: "master \(name)")
            }
            // Both sides edit all six, differently: six conflicts.
            for name in files {
                try "theirs\n".write(to: repo.worktree.appending(path: name), atomically: true, encoding: .utf8)
            }
            _ = try repo.git("add", "-A", in: repo.worktree)
            _ = try repo.git("commit", "-q", "--no-verify", "-m", "wt all", in: repo.worktree)
            for name in files {
                try "ours\n".write(to: repo.root.appending(path: name), atomically: true, encoding: .utf8)
            }
            _ = try repo.git("add", "-A")
            _ = try repo.git("commit", "-q", "--no-verify", "-m", "master all")
            let info = try #require(WorktreeProbe().fresh(forCwd: repo.wt))

            let merge = GitMerge.perform(.noFF, on: info).said
            #expect(merge.contains("conflicts in a.txt, p.txt, q.txt, r.txt (+2)"), "\(merge)")
            #expect(merge.contains("backed out"), "\(merge)")
            let update = GitUpdate.perform(on: info, worktree: repo.wt).said
            #expect(update.contains("conflicts in a.txt, p.txt, q.txt, r.txt (+2)"), "\(update)")
            #expect(update.contains("backed out"), "\(update)")
            // Both trees back where they started, neither mid-merge.
            #expect(try repo.git("status", "--porcelain", "--untracked-files=no") == "")
            #expect(try repo.git("status", "--porcelain", "--untracked-files=no", in: repo.worktree) == "")
        }
    }

    // MARK: update from master (slice 6)

    @Test func anUpdateMergesMasterIntoTheWorktree() throws {
        try withRepo { repo in
            try repo.commit("b.txt", "two\n", message: "wt one", worktree: true)
            try repo.commit("c.txt", "three\n", message: "master one")
            try repo.commit("d.txt", "four\n", message: "master two")
            let master = try repo.git("rev-parse", "master")
            let tip = try repo.git("rev-parse", "worktree-t")
            let probe = WorktreeProbe()
            let info = try #require(probe.fresh(forCwd: repo.wt))
            #expect(info.behind == 2 && info.canUpdate)
            let outcome = GitUpdate.perform(on: info, worktree: repo.wt)
            #expect(outcome.merged, "\(outcome.said)")
            #expect(outcome.said.hasPrefix("merged master → worktree-t (2 commits, merge commit ") && outcome.ask == nil)
            // A merge commit on the branch, master untouched, and the
            // session's own commit still its parent — a merge, not a rewrite.
            #expect(try repo.git("rev-parse", "master") == master)
            #expect(try repo.git("log", "--format=%s", "-1", in: repo.worktree) == "Merge master into worktree-t (2 commits)")
            #expect(try repo.git("rev-parse", "HEAD^1", in: repo.worktree) == tip)
            #expect(try repo.git("rev-parse", "HEAD^2", in: repo.worktree) == master)
            let after = try #require(probe.fresh(forCwd: repo.wt))
            #expect(after.behind == 0 && after.ahead == 2 && !after.canUpdate && after.canFastForward)
            #expect(try String(contentsOf: repo.worktree.appending(path: "d.txt"), encoding: .utf8) == "four\n")
            // A second update has nothing to bring.
            #expect(GitUpdate.perform(on: after, worktree: repo.wt).said.hasPrefix("nothing to update"))
        }
    }

    @Test func aBranchWithNoWorkFastForwardsToMaster() throws {
        try withRepo { repo in
            try repo.commit("c.txt", "three\n", message: "master one")
            let info = try #require(WorktreeProbe().fresh(forCwd: repo.wt))
            #expect(info.ahead == 0 && info.behind == 1)
            let outcome = GitUpdate.perform(on: info, worktree: repo.wt)
            #expect(outcome.merged && outcome.said.hasPrefix("fast-forwarded worktree-t to master (1 commit, now "), "\(outcome.said)")
            #expect(try repo.git("rev-parse", "worktree-t") == repo.git("rev-parse", "master"))
        }
    }

    @Test func anUpdateRefusesADirtyWorktree() throws {
        try withRepo { repo in
            try repo.commit("c.txt", "three\n", message: "master one")
            try "edited\n".write(to: repo.worktree.appending(path: "a.txt"), atomically: true, encoding: .utf8)
            let info = try #require(WorktreeProbe().fresh(forCwd: repo.wt))
            let before = try repo.git("rev-parse", "worktree-t")
            let outcome = GitUpdate.perform(on: info, worktree: repo.wt)
            #expect(!outcome.merged && outcome.said.contains("1 uncommitted change (a.txt)"), "\(outcome.said)")
            #expect(try repo.git("rev-parse", "worktree-t") == before)
            // An untracked file is not a change in flight: the merge goes.
            try "edited\n".write(to: repo.worktree.appending(path: "a.txt"), atomically: true, encoding: .utf8)
            _ = try repo.git("checkout", "-q", "--", "a.txt", in: repo.worktree)
            try "scratch\n".write(to: repo.worktree.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
            #expect(GitUpdate.perform(on: info, worktree: repo.wt).merged)
        }
    }

    @Test func anUpdateConflictBacksOutAndOffersTheSession() throws {
        try withRepo { repo in
            try repo.commit("a.txt", "theirs\n", message: "wt edit", worktree: true)
            try repo.commit("a.txt", "ours\n", message: "master edit")
            let before = try repo.git("rev-parse", "worktree-t")
            let master = try repo.git("rev-parse", "master")
            let info = try #require(WorktreeProbe().fresh(forCwd: repo.wt))
            let outcome = GitUpdate.perform(on: info, worktree: repo.wt)
            #expect(!outcome.merged, "\(outcome.said)")
            // Exact, off a real collision: `loop-301` produced this line
            // with its own names and nothing else differing (2026-09-17).
            // The `— ask the session to merge <tip>` clause was read by no
            // test until that landed, and it is half of what the HUD's
            // button promises.
            #expect(outcome.said == "merge master → worktree-t conflicts in a.txt; backed out, worktree-t untouched — ask the session to merge master",
                    "\(outcome.said)")
            #expect(outcome.ask == "Merge master into this branch and resolve the conflicts.")
            #expect(try repo.git("rev-parse", "worktree-t") == before)
            #expect(try repo.git("status", "--porcelain", "--untracked-files=no", in: repo.worktree) == "")
            #expect(try String(contentsOf: repo.worktree.appending(path: "a.txt"), encoding: .utf8) == "theirs\n")
            // Not mid-merge: no MERGE_HEAD left behind in the worktree's gitdir.
            let layout = try #require(WorktreeProbe.layout(of: repo.wt))
            #expect(!FileManager.default.fileExists(atPath: layout.gitdir + "/MERGE_HEAD"))
            // The other side of the back-out, the mirror of what merge's
            // owes the worker: the base was merged *from* and never moved.
            #expect(try repo.git("rev-parse", "master") == master)
            #expect(try repo.git("status", "--porcelain", "--untracked-files=no") == "")
        }
    }

    /// `--keep-conflicts`: the back-out's opposite, for the lane whose own
    /// `git merge` the classifier refuses (attrition 1293, 86 minutes for
    /// a human). The tree is left mid-merge with its markers, every path is
    /// named uncut, and what is left to do — resolve, add, commit — is the
    /// part a lane may do; the commit then lands as master's merge.
    @Test func aKeptConflictLeavesTheMergeToResolve() throws {
        try withRepo { repo in
            let files = ["a.txt", "p.txt", "q.txt", "r.txt", "s.txt"]
            for name in files where name != "a.txt" {
                try repo.commit(name, "base\n", message: "master \(name)")
            }
            for name in files {
                try "theirs\n".write(to: repo.worktree.appending(path: name), atomically: true, encoding: .utf8)
            }
            _ = try repo.git("add", "-A", in: repo.worktree)
            _ = try repo.git("commit", "-q", "--no-verify", "-m", "wt all", in: repo.worktree)
            for name in files {
                try "ours\n".write(to: repo.root.appending(path: name), atomically: true, encoding: .utf8)
            }
            _ = try repo.git("add", "-A")
            _ = try repo.git("commit", "-q", "--no-verify", "-m", "master all")
            let before = try repo.git("rev-parse", "worktree-t")
            let master = try repo.git("rev-parse", "master")
            let info = try #require(WorktreeProbe().fresh(forCwd: repo.wt))

            let outcome = GitUpdate.perform(on: info, worktree: repo.wt, keepConflicts: true)
            #expect(!outcome.merged)
            #expect(outcome.said == "merge master → worktree-t conflicts in a.txt, p.txt, q.txt, r.txt (+1); left in place, worktree-t mid-merge — resolve, `git add` and `git commit` to finish (`git merge --abort` backs out)",
                    "\(outcome.said)")
            // Uncut: the sentence names four, the caller resolving needs five.
            #expect(outcome.conflicts == files)
            #expect(outcome.ask?.hasPrefix("Merging master into this branch left conflicts in a.txt") == true)
            let layout = try #require(WorktreeProbe.layout(of: repo.wt))
            #expect(FileManager.default.fileExists(atPath: layout.gitdir + "/MERGE_HEAD"))
            #expect(try String(contentsOf: repo.worktree.appending(path: "a.txt"), encoding: .utf8).contains("<<<<<<<"))
            // Nothing committed for the lane, nothing moved on master.
            #expect(try repo.git("rev-parse", "worktree-t") == before)
            #expect(try repo.git("rev-parse", "master") == master)

            // A second update meets a tree mid-merge, and refuses it as
            // dirty — it never stacks a merge on an unresolved one.
            let again = GitUpdate.perform(on: try #require(WorktreeProbe().fresh(forCwd: repo.wt)), worktree: repo.wt, keepConflicts: true)
            #expect(!again.merged && again.conflicts == nil && again.said.contains("uncommitted"), "\(again.said)")

            // The lane's half: resolve, add, commit — a merge commit with
            // master as its second parent.
            for name in files {
                try "both\n".write(to: repo.worktree.appending(path: name), atomically: true, encoding: .utf8)
            }
            _ = try repo.git("add", "-A", in: repo.worktree)
            _ = try repo.git("commit", "-q", "--no-edit", "--no-verify", in: repo.worktree)
            #expect(try repo.git("rev-parse", "HEAD^1", in: repo.worktree) == before)
            #expect(try repo.git("rev-parse", "HEAD^2", in: repo.worktree) == master)
        }
    }

    /// Kept only when git stopped on files. An update that fails before
    /// staging a conflict — an untracked file master would overwrite —
    /// has nothing to resolve, and backs out exactly as it always did.
    @Test func aKeptUpdateWithNoConflictedFilesStillBacksOut() throws {
        try withRepo { repo in
            try repo.commit("b.txt", "two\n", message: "wt one", worktree: true)
            try repo.commit("n.txt", "master's\n", message: "master adds n")
            try "mine, untracked\n".write(to: repo.worktree.appending(path: "n.txt"), atomically: true, encoding: .utf8)
            let info = try #require(WorktreeProbe().fresh(forCwd: repo.wt))
            let outcome = GitUpdate.perform(on: info, worktree: repo.wt, keepConflicts: true)
            #expect(!outcome.merged && outcome.conflicts == nil, "\(outcome.said)")
            #expect(outcome.said.contains("backed out"), "\(outcome.said)")
            let layout = try #require(WorktreeProbe.layout(of: repo.wt))
            #expect(!FileManager.default.fileExists(atPath: layout.gitdir + "/MERGE_HEAD"))
        }
    }

    @Test func theWireCarriesAsk() throws {
        let data = try JSONEncoder().encode(ControlRequest.ask(id: SessionRef(id: "a1b2"), prompt: "Merge master into this branch and resolve the conflicts."))
        let back = try JSONDecoder().decode(ControlRequest.self, from: data)
        if case .ask(let ref, let prompt) = back {
            #expect(ref == SessionRef(id: "a1b2") && prompt.hasPrefix("Merge master"))
        } else { Issue.record("not ask") }
    }

    @Test func theStrategyFlagsAreGitsWords() {
        #expect(MergeStrategy.parse(flag: "--ff-only") == .ffOnly)
        #expect(MergeStrategy.parse(flag: "--no-ff") == .noFF)
        #expect(MergeStrategy.parse(flag: "--squash") == .squash)
        #expect(MergeStrategy.parse(flag: "--rebase") == nil)
    }

    @Test func theRowCarriesTheWorktreeAcrossTheWire() throws {
        let info = WorktreeInfo(branch: "worktree-v2", base: "master", ahead: 3, behind: 0, repo: "/x/ccc")
        let session = Session(id: "a1b2", cwd: "/x/ccc/.claude/worktrees/v2", kind: .background, startedAt: Date())
        let row = SessionRow(session: session, model: nil, attached: false, worktree: info)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(row)
        let back = try JSONDecoder.roster.decode(SessionRow.self, from: data)
        #expect(back.worktree == info)
        // An older ccc sends no such key, and a malformed one is nil, never a failed row.
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["worktree"] = nil
        let bare = try JSONDecoder.roster.decode(SessionRow.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(bare.worktree == nil)
        object["worktree"] = ["branch": 7]
        let odd = try JSONDecoder.roster.decode(SessionRow.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(odd.worktree == nil)
    }

    @Test func remoteMergeIsTheFarSidesVerb() {
        let host = Host(name: "studio", ssh: "studio", claude: "~/.local/bin/claude", ccc: "/opt/homebrew/bin/ccc")
        let cli = ClaudeCLI(executable: "~/.local/bin/claude", host: host)
        let argv = cli.mergeArgv(.squash, id: "a1b2")
        #expect(argv?.suffix(3) == ["/opt/homebrew/bin/ccc", "merge", "a1b2"] || argv?.suffix(4) == ["/opt/homebrew/bin/ccc", "merge", "a1b2", "--squash"])
        #expect(argv?.last == "--squash")
        #expect(ClaudeCLI(executable: "/x/claude").mergeArgv(.ffOnly, id: "a1b2") == nil)
    }
}

/// Slice 2: what origin does not have. A bare repo stands in for GitHub;
/// pushes and local commits move `⇡` the way a hand would see it.
@Suite(.serialized) struct UnpushedTests {
    private func withOrigin(_ body: (URL, URL, (String, URL) throws -> String) throws -> Void) throws {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-up-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let origin = dir.appending(path: "origin.git"), root = dir.appending(path: "repo")
        func git(_ line: String, _ at: URL) throws -> String {
            try Git.run(WorktreeProbe.defaultGit, ["-C", at.path] + line.split(separator: " ").map(String.init)).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = try Git.run(WorktreeProbe.defaultGit, ["init", "-q", "--bare", origin.path])
        _ = try Git.run(WorktreeProbe.defaultGit, ["init", "-q", "-b", "master", root.path])
        _ = try git("config user.email t@example.com", root)
        _ = try git("config user.name t", root)
        try "one\n".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        _ = try git("add a.txt", root)
        _ = try git("commit -q --no-verify -m first", root)
        _ = try git("remote add origin \(origin.path)", root)
        _ = try git("push -q -u origin master", root)
        try FileManager.default.createDirectory(at: root.appending(path: ".claude"), withIntermediateDirectories: true)
        let wt = root.appending(path: ".claude/worktrees/t")
        _ = try git("worktree add -q -b worktree-t \(wt.path) master", root)
        try body(root, wt, git)
    }

    private func commit(_ name: String, in dir: URL, _ git: (String, URL) throws -> String) throws {
        try "x\n".write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
        _ = try git("add \(name)", dir)
        _ = try git("commit -q --no-verify -m \(name)", dir)
    }

    @Test func noOriginMeansNoReading() throws {
        // The slice-1 suite's repos have no remote: unpushed stays nil there.
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-noorigin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try Git.run(WorktreeProbe.defaultGit, ["init", "-q", "-b", "master", dir.path])
        #expect(!WorktreeProbe.hasOrigin(commonDir: dir.appending(path: ".git").path))
    }

    @Test func unpushedFollowsCommitsAndPushes() throws {
        try withOrigin { root, wt, git in
            let probe = WorktreeProbe()
            // A branch that was never pushed, level with a pushed master: nothing unpushed.
            let fresh = try #require(probe.info(forCwd: wt.path))
            #expect(fresh.unpushed == 0 && fresh.baseUnpushed == 0)
            #expect(fresh.summary == "worktree-t level" && fresh.baseMark == nil)
            try commit("b.txt", in: wt, git)
            try commit("c.txt", in: wt, git)
            let two = try #require(probe.info(forCwd: wt.path))
            #expect(two.ahead == 2 && two.unpushed == 2)
            #expect(two.summary == "worktree-t ↑2 ⇡2")
            _ = try git("push -q -u origin worktree-t", wt)
            let pushed = try #require(probe.info(forCwd: wt.path))
            #expect(pushed.ahead == 2 && pushed.unpushed == 0, "a push moves origin/<branch>, which is in the cache key")
            #expect(pushed.summary == "worktree-t ↑2")
            // Fast-forward master here: master is now what the other Mac cannot see.
            let info = try #require(probe.fresh(forCwd: wt.path))
            #expect(GitMerge.perform(.ffOnly, on: info).merged)
            let landed = try #require(probe.info(forCwd: wt.path))
            #expect(landed.ahead == 0 && landed.unpushed == 0 && landed.baseUnpushed == 2)
            #expect(landed.baseMark == "⇡2" && landed.summary == "worktree-t level")
            _ = try git("push -q origin master", root)
            #expect(probe.info(forCwd: wt.path)?.baseUnpushed == 0)
        }
    }

    /// The poller's probe lives as long as the app. A default branch
    /// renamed under it kept the old name cached, and the column blanked
    /// for every worktree of that repo until relaunch (found 2026-09-04):
    /// a cached name is trusted only while it still resolves.
    @Test func aRenamedDefaultBranchIsFoundAgain() throws {
        try withOrigin { root, wt, git in
            let probe = WorktreeProbe()
            #expect(try #require(probe.info(forCwd: wt.path)).base == "master")
            _ = try git("branch -m master main", root)
            _ = try git("push -q -u origin main", root)
            _ = try git("symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main", root)
            #expect(try #require(probe.info(forCwd: wt.path)).base == "main")
        }
    }

    @Test func aSliceOneRowStillDecodes() throws {
        let data = Data(#"{"branch":"worktree-v2","base":"master","ahead":3,"behind":0,"repo":"/x"}"#.utf8)
        let info = try JSONDecoder().decode(WorktreeInfo.self, from: data)
        #expect(info.ahead == 3 && info.unpushed == nil && info.baseUnpushed == nil)
    }
}

/// Slice 3: the push, against the same bare origin. Never forced: a
/// moved remote is git's refusal, passed through, and nothing changes.
@Suite(.serialized) struct PushTests {
    private func withOrigin(_ body: (URL, URL, (String, URL) throws -> String) throws -> Void) throws {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-push-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let origin = dir.appending(path: "origin.git"), root = dir.appending(path: "repo")
        func git(_ line: String, _ at: URL) throws -> String {
            try Git.run(WorktreeProbe.defaultGit, ["-C", at.path] + line.split(separator: " ").map(String.init)).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = try Git.run(WorktreeProbe.defaultGit, ["init", "-q", "--bare", origin.path])
        _ = try Git.run(WorktreeProbe.defaultGit, ["init", "-q", "-b", "master", root.path])
        _ = try git("config user.email t@example.com", root)
        _ = try git("config user.name t", root)
        try "one\n".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        _ = try git("add a.txt", root)
        _ = try git("commit -q --no-verify -m first", root)
        _ = try git("remote add origin \(origin.path)", root)
        _ = try git("push -q -u origin master", root)
        try FileManager.default.createDirectory(at: root.appending(path: ".claude"), withIntermediateDirectories: true)
        let wt = root.appending(path: ".claude/worktrees/t")
        _ = try git("worktree add -q -b worktree-t \(wt.path) master", root)
        try body(root, wt, git)
    }

    private func commit(_ name: String, in dir: URL, _ git: (String, URL) throws -> String) throws {
        try "x\n".write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
        _ = try git("add \(name)", dir)
        _ = try git("commit -q --no-verify -m \(name)", dir)
    }

    @Test func pushesTheBranchThenMasterAndClearsTheMarks() throws {
        try withOrigin { root, wt, git in
            let probe = WorktreeProbe()
            try commit("b.txt", in: wt, git)
            let before = try #require(probe.fresh(forCwd: wt.path))
            #expect(before.unpushed == 1)
            // Nothing on master yet: that target says so and sends nothing.
            let idle = GitPush.perform(.base, on: before)
            #expect(!idle.merged && idle.said.hasPrefix("nothing to push"))
            let pushed = GitPush.perform(.branch, on: before)
            #expect(pushed.merged, "\(pushed.said)")
            #expect(pushed.said == "pushed worktree-t → origin (1 commit)")
            #expect(try git("rev-parse origin/worktree-t", root) == git("rev-parse worktree-t", root))
            #expect(probe.fresh(forCwd: wt.path)?.unpushed == 0)
            // Land it, then master is the one to send.
            let landed = try #require(probe.fresh(forCwd: wt.path))
            #expect(GitMerge.perform(.ffOnly, on: landed).merged)
            let after = try #require(probe.fresh(forCwd: wt.path))
            #expect(after.baseUnpushed == 1)
            let master = GitPush.perform(.base, on: after)
            #expect(master.merged && master.said == "pushed master → origin (1 commit)")
            #expect(probe.fresh(forCwd: wt.path)?.baseUnpushed == 0)
        }
    }

    @Test func aMovedRemoteIsRefusedAndNothingChanges() throws {
        try withOrigin { root, wt, git in
            // Someone else pushed to origin/master; ours diverged.
            let other = root.deletingLastPathComponent().appending(path: "other")
            _ = try Git.run(WorktreeProbe.defaultGit, ["clone", "-q", root.deletingLastPathComponent().appending(path: "origin.git").path, other.path])
            _ = try git("config user.email o@example.com", other)
            _ = try git("config user.name o", other)
            try commit("theirs.txt", in: other, git)
            _ = try git("push -q origin master", other)
            try commit("ours.txt", in: root, git)
            let probe = WorktreeProbe()
            let info = try #require(probe.fresh(forCwd: wt.path))
            #expect(info.baseUnpushed == 1, "as of the last fetch, master is one ahead — the reading never fetches")
            let outcome = GitPush.perform(.base, on: info)
            #expect(!outcome.merged)
            #expect(outcome.said.contains("origin/master has moved"), "\(outcome.said)")
            #expect(try git("rev-parse origin/master", other) != git("rev-parse master", root))
        }
    }

    @Test func noOriginIsSaidNotTried() {
        let info = WorktreeInfo(branch: "worktree-x", base: "master", ahead: 1, behind: 0, repo: "/nowhere")
        let outcome = GitPush.perform(.branch, on: info)
        #expect(!outcome.merged && outcome.said.contains("no origin"))
    }

    @Test func remotePushIsTheFarSidesVerb() {
        let host = Host(name: "studio", ssh: "studio", claude: "~/.local/bin/claude", ccc: "/opt/homebrew/bin/ccc")
        let cli = ClaudeCLI(executable: "~/.local/bin/claude", host: host)
        #expect(cli.pushArgv(.branch, id: "a1b2")?.suffix(3) == ["/opt/homebrew/bin/ccc", "push", "a1b2"])
        #expect(cli.pushArgv(.base, id: "a1b2")?.suffix(4) == ["/opt/homebrew/bin/ccc", "push", "a1b2", "--base"])
    }
}

/// Slice 4: the shell pane's words. Local is the login shell with the
/// PTY's cwd; remote is the attach prefix and a remote `cd`, `$SHELL`
/// left for the far side.
@Suite struct ShellArgvTests {
    @Test func localIsTheLoginShell() {
        let cli = ClaudeCLI(executable: "/x/claude")
        #expect(cli.shellArgv(cwd: "/Users/x/code", environment: ["SHELL": "/bin/zsh"]) == ["/bin/zsh", "-l"])
        // A SHELL that is not there falls back to zsh rather than failing the exec.
        #expect(cli.shellArgv(cwd: "/Users/x/code", environment: ["SHELL": "/nope/fish"]) == ["/bin/zsh", "-l"])
        #expect(cli.shellArgv(cwd: "/Users/x/code", environment: [:]) == ["/bin/zsh", "-l"])
    }

    @Test func remoteIsTheAttachPrefixAndACd() {
        let host = Host(name: "studio", ssh: "rf-studio@studio", claude: "~/.local/bin/claude")
        let cli = ClaudeCLI(executable: "~/.local/bin/claude", host: host)
        let argv = cli.shellArgv(cwd: "/Users/rf-studio/code/fun/ccc/.claude/worktrees/v2")
        #expect(argv.first == "/usr/bin/ssh" && argv.contains("-t"))
        #expect(argv.dropLast().last == "rf-studio@studio")
        #expect(argv.last == "cd /Users/rf-studio/code/fun/ccc/.claude/worktrees/v2 && exec $SHELL -l")
        // A folder with a space is quoted for the remote shell, once.
        let odd = cli.shellArgv(cwd: "/Users/rf-studio/my code/it's")
        #expect(odd.last == "cd '/Users/rf-studio/my code/it'\\''s' && exec $SHELL -l")
    }

    @Test func theWireCarriesShell() throws {
        let data = try JSONEncoder().encode(ControlRequest.shell(id: SessionRef(host: "studio", id: "a1b2")))
        let back = try JSONDecoder().decode(ControlRequest.self, from: data)
        if case .shell(let ref, let repo) = back { #expect(ref == SessionRef(host: "studio", id: "a1b2") && repo == nil) } else { Issue.record("not shell") }
        let close = try JSONDecoder().decode(ControlRequest.self, from: JSONEncoder().encode(ControlRequest.shellClose))
        if case .shellClose = close {} else { Issue.record("not shellClose") }
    }
}

/// Slice 7: fetch and pull, against a bare origin and a second clone that
/// stands in for the other Mac. The reading never fetches; the verb does,
/// once, and the marks move with it.
@Suite(.serialized) struct FetchPullTests {
    private func withOrigin(_ body: (URL, URL, URL, (String, URL) throws -> String) throws -> Void) throws {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-fetch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let origin = dir.appending(path: "origin.git"), root = dir.appending(path: "repo"), other = dir.appending(path: "other")
        func git(_ line: String, _ at: URL) throws -> String {
            try Git.run(WorktreeProbe.defaultGit, ["-C", at.path] + line.split(separator: " ").map(String.init)).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = try Git.run(WorktreeProbe.defaultGit, ["init", "-q", "--bare", "-b", "master", origin.path])
        _ = try Git.run(WorktreeProbe.defaultGit, ["init", "-q", "-b", "master", root.path])
        _ = try git("config user.email t@example.com", root)
        _ = try git("config user.name t", root)
        try "one\n".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        _ = try git("add a.txt", root)
        _ = try git("commit -q --no-verify -m first", root)
        _ = try git("remote add origin \(origin.path)", root)
        _ = try git("push -q -u origin master", root)
        try FileManager.default.createDirectory(at: root.appending(path: ".claude"), withIntermediateDirectories: true)
        let wt = root.appending(path: ".claude/worktrees/t")
        _ = try git("worktree add -q -b worktree-t \(wt.path) master", root)
        _ = try Git.run(WorktreeProbe.defaultGit, ["clone", "-q", origin.path, other.path])
        _ = try git("config user.email o@example.com", other)
        _ = try git("config user.name o", other)
        try body(root, wt, other, git)
    }

    private func commit(_ name: String, in dir: URL, _ git: (String, URL) throws -> String) throws {
        try "x\n".write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
        _ = try git("add \(name)", dir)
        _ = try git("commit -q --no-verify -m \(name)", dir)
    }

    @Test func fetchReadsTheOtherMacsPushAndPullFastForwards() throws {
        try withOrigin { root, wt, other, git in
            try commit("theirs.txt", in: other, git)
            try commit("theirs2.txt", in: other, git)
            _ = try git("push -q origin master", other)
            let probe = WorktreeProbe()
            // As of the last fetch — which was the push at setup — nothing.
            let stale = try #require(probe.fresh(forCwd: wt.path))
            #expect(stale.baseUnpulled == 0 && !stale.canPull && stale.baseMark == nil)
            #expect(GitPull.perform(on: stale).said.hasPrefix("nothing to pull"))
            let fetched = GitFetch.perform(repo: root.path)
            #expect(fetched.merged && fetched.said.hasPrefix("fetched origin ("), "\(fetched.said)")
            let fresh = try #require(probe.fresh(forCwd: wt.path))
            #expect(fresh.baseUnpulled == 2 && fresh.canPull && fresh.baseMark == "⇣2")
            #expect(fresh.originStanding == "master has 2 unpulled")
            let pulled = GitPull.perform(on: fresh)
            #expect(pulled.merged && pulled.said.hasPrefix("pulled origin/master → master (2 commits, now "), "\(pulled.said)")
            #expect(try git("rev-parse master", root) == git("rev-parse origin/master", root))
            let level = try #require(probe.fresh(forCwd: wt.path))
            #expect(level.baseUnpulled == 0 && level.behind == 2, "the worktree is now behind the moved master")
            #expect(level.originStanding == "level with origin")
        }
    }

    @Test func pullRefusesADivergedMasterAndNamesTheWayOut() throws {
        try withOrigin { root, wt, other, git in
            try commit("theirs.txt", in: other, git)
            _ = try git("push -q origin master", other)
            try commit("ours.txt", in: root, git)
            _ = GitFetch.perform(repo: root.path)
            let info = try #require(WorktreeProbe().fresh(forCwd: wt.path))
            #expect(info.baseUnpulled == 1 && info.baseUnpushed == 1 && info.baseMark == "⇡1 ⇣1")
            let before = try git("rev-parse master", root)
            let outcome = GitPull.perform(on: info)
            #expect(!outcome.merged && outcome.said.contains("push master first"), "\(outcome.said)")
            #expect(try git("rev-parse master", root) == before)
            // And a dirty checkout is refused before anything else is tried.
            try "dirty\n".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
            #expect(GitPull.perform(on: info).said.contains("1 uncommitted change (a.txt)"))
        }
    }

    @Test func theBranchReadsUnpulledOnceOriginHasIt() throws {
        try withOrigin { root, wt, other, git in
            let probe = WorktreeProbe()
            try commit("b.txt", in: wt, git)
            let unpushed = try #require(probe.fresh(forCwd: wt.path))
            #expect(unpushed.unpulled == nil, "origin has no such branch yet")
            _ = try git("push -q -u origin worktree-t", wt)
            _ = try git("fetch -q origin", other)
            _ = try git("checkout -q worktree-t", other)
            try commit("c.txt", in: other, git)
            _ = try git("push -q origin worktree-t", other)
            let stale = try #require(probe.fresh(forCwd: wt.path))
            #expect(stale.unpulled == 0)
            _ = GitFetch.perform(repo: root.path)
            let fresh = try #require(probe.fresh(forCwd: wt.path))
            #expect(fresh.unpulled == 1 && fresh.unpushed == 0)
            #expect(fresh.summary == "worktree-t ↑1 ⇣1")
            #expect(fresh.originStanding == "worktree-t 1 unpulled")
        }
    }

    @Test func noOriginIsSaidNotTried() {
        let info = WorktreeInfo(branch: "worktree-x", base: "master", ahead: 1, behind: 0, repo: "/nowhere")
        #expect(GitPull.perform(on: info).said.contains("no origin/master"))
        #expect(!GitFetch.perform(repo: "/nowhere").merged)
    }

    // MARK: the root reading — `ccc pull --repo`, which has no session

    private func resolved(_ path: String) -> String {
        URL(filePath: path).resolvingSymlinksInPath().path
    }

    /// The reading `info(forCwd:)` refuses to make: a main checkout sitting
    /// on its own default branch. `layout` returns nil for it (a directory
    /// `.git`) and `info` would return nil again on `branch == base`, so
    /// this is its own door — and it must carry the base's standing, which
    /// is the only thing `GitPull` reads.
    @Test func theRootReadingAnswersForACheckoutOnItsDefaultBranch() throws {
        try withOrigin { root, wt, other, git in
            let probe = WorktreeProbe()
            #expect(probe.fresh(forCwd: root.path) == nil, "the worktree reading still declines the root")
            let before = try #require(probe.root(forRepo: root.path))
            #expect(before.base == "master" && before.branch == "master")
            #expect(resolved(before.repo) == resolved(root.path))
            #expect(before.baseUnpulled == 0 && before.baseUnpushed == 0)
            #expect(before.originStanding == "level with origin")
            try commit("theirs.txt", in: other, git)
            _ = try git("push -q origin master", other)
            _ = GitFetch.perform(repo: root.path)
            let after = try #require(probe.root(forRepo: root.path))
            #expect(after.baseUnpulled == 1 && after.canPull && after.baseMark == "⇣1")
            // The branch's own ⇡⇣ stay nil: they would only say the base's
            // twice, and `originStanding` would print it twice with them.
            #expect(after.unpushed == nil && after.unpulled == nil)
            #expect(after.originStanding == "master has 1 unpulled")
        }
    }

    /// The root form fast-forwards the same checkout the ref form does,
    /// through the same `GitPull.perform` — that is what "GitPull
    /// untouched" has to mean.
    @Test func theRootFormFastForwardsTheMainCheckout() throws {
        try withOrigin { root, wt, other, git in
            try commit("theirs.txt", in: other, git)
            _ = try git("push -q origin master", other)
            _ = GitFetch.perform(repo: root.path)
            let info = try #require(WorktreeProbe().root(forRepo: root.path))
            let outcome = GitPull.perform(on: info)
            #expect(outcome.merged && outcome.said.hasPrefix("pulled origin/master → master (1 commit, now "), "\(outcome.said)")
            #expect(try git("rev-parse master", root) == git("rev-parse origin/master", root))
        }
    }

    /// A path inside a worktree answers for the ROOT, because `pull <ref>`
    /// already does exactly that with a session's cwd. One verb, one
    /// answer, whichever way the checkout was named.
    @Test func aWorktreePathAnswersForItsRoot() throws {
        try withOrigin { root, wt, other, git in
            let probe = WorktreeProbe()
            let fromWorktree = try #require(probe.root(forRepo: wt.path))
            let fromRoot = try #require(probe.root(forRepo: root.path))
            #expect(resolved(fromWorktree.repo) == resolved(fromRoot.repo))
            #expect(fromWorktree.base == "master" && fromWorktree.branch == "master")
        }
    }

    /// The root checkout is only pullable while it is ON the base — the
    /// guard `GitPull` already had, now reachable without a session.
    @Test func aRootOffItsDefaultBranchIsRefused() throws {
        try withOrigin { root, wt, other, git in
            try commit("theirs.txt", in: other, git)
            _ = try git("push -q origin master", other)
            _ = GitFetch.perform(repo: root.path)
            _ = try git("checkout -q -b elsewhere", root)
            let info = try #require(WorktreeProbe().root(forRepo: root.path))
            let outcome = GitPull.perform(on: info)
            #expect(!outcome.merged && outcome.said.contains("is on elsewhere, not master"), "\(outcome.said)")
        }
    }

    @Test func aFolderThatIsNoRepositoryHasNoRootReading() throws {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-norepo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(WorktreeProbe().root(forRepo: dir.path) == nil)
        #expect(WorktreeProbe.rootLayout(of: dir.path) == nil)
    }

    @Test func theRowCarriesTheMarksAcrossTheWire() throws {
        let info = WorktreeInfo(branch: "worktree-v2", base: "master", ahead: 3, behind: 0, repo: "/x/ccc",
                                unpushed: 1, baseUnpushed: 0, unpulled: 2, baseUnpulled: 1)
        let data = try JSONEncoder().encode(info)
        #expect(try JSONDecoder().decode(WorktreeInfo.self, from: data) == info)
        // A slice-6 ccc on the far side sends neither key.
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["unpulled"] = nil
        object["baseUnpulled"] = nil
        let older = try JSONDecoder().decode(WorktreeInfo.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(older.unpulled == nil && older.baseUnpulled == nil && older.unpushed == 1)
    }
}

/// The shell pane's "free" reading: the foreground process group of the
/// PTY, from the kernel. A shell at its prompt is replaceable; a shell
/// with a job in front of it is not.
@Suite struct ShellPromptTests {
    @MainActor
    @Test func atPromptFollowsTheForegroundJob() async throws {
        let host = HeadlessHost(cols: 40, rows: 6)
        let session = try AttachSession(ref: SessionRef(id: "t"), argv: ["/bin/sh", "-i"], host: host,
                                        options: .init(cols: 40, rows: 6))
        defer { session.terminate() }
        // Give the shell a moment to come up and take the terminal.
        for _ in 0..<50 where !session.isAtPrompt { try await Task.sleep(for: .milliseconds(20)) }
        #expect(session.isAtPrompt)
        session.send(text: "sleep 5\n")
        for _ in 0..<50 where session.isAtPrompt { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!session.isAtPrompt, "a foreground job owns the terminal")
        session.send(text: "\u{03}")   // Ctrl+C ends the job; the shell is back
        for _ in 0..<50 where !session.isAtPrompt { try await Task.sleep(for: .milliseconds(20)) }
        #expect(session.isAtPrompt)
    }
}
