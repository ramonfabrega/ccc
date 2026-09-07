import Foundation
import Testing

@testable import CCCKit

/// Item 24: a worktree ccc cut is nobody's to clean.
///
/// `ccc rm` passes `claude rm` through and the harness deletes the
/// worktree *it* made. It did not make this one: `--base` cuts the tree
/// here and hands the harness a plain cwd, so the daemon never learns it
/// is a worktree. Measured 2026-09-06 while proving item 23 — `ccc rm
/// 0f7b8c26` answered `removed`, exit 0, and left the tree, the branch
/// and the `ccc-base` record on disk; `git worktree remove --force` and
/// `git branch -D` finished it by hand, and every ccc-cut worktree on the
/// fleet was in that state.
///
/// The mark is the whole ownership test — `branch.<b>.ccc-cut`, written
/// by `createWorktree` and nothing else — and git's own refusals are the
/// whole guard.
@Suite(.serialized) struct CutWorktreeTests {
    private struct Repo {
        let root: URL
        var path: String { root.path }
        @discardableResult
        func git(_ args: String...) throws -> String {
            try Git.run(WorktreeProbe.defaultGit, ["-C", root.path] + args).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func write(_ path: String, _ text: String) throws {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        var config: String {
            (try? String(contentsOfFile: root.appending(path: ".git/config").path, encoding: .utf8)) ?? ""
        }
        /// The worktrees git itself still lists, by path.
        func listed() throws -> Set<String> {
            var paths: Set<String> = []
            for line in try git("worktree", "list", "--porcelain").split(separator: "\n") where line.hasPrefix("worktree ") {
                paths.insert(URL(filePath: String(line.dropFirst("worktree ".count))).standardizedFileURL.path)
            }
            return paths
        }
        func branches() throws -> Set<String> {
            Set(try git("for-each-ref", "--format=%(refname:short)", "refs/heads").split(separator: "\n").map(String.init))
        }
    }

    /// master with one commit — the smallest repository `createWorktree`
    /// will cut from.
    private func withRepo(_ body: (Repo) throws -> Void) throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-cut-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = Repo(root: URL(filePath: root.standardizedFileURL.path))
        try repo.git("init", "-q", "-b", "master")
        try repo.git("config", "user.email", "t@example.com")
        try repo.git("config", "user.name", "t")
        try repo.write("a.txt", "one\n")
        try repo.git("add", "a.txt")
        try repo.git("commit", "-q", "--no-verify", "-m", "first")
        try body(repo)
    }

    // MARK: the mark

    @Test func theCutIsRecordedAgainstTheBranch() throws {
        try withRepo { repo in
            let made = try WorktreeProbe.createWorktree(named: "w", base: "master", repo: repo.path)
            #expect(WorktreeProbe.recordedCuts(in: repo.config)["worktree-w"] == made.path)
            // The base still goes in beside it: two keys, two questions.
            #expect(WorktreeProbe.recordedBases(in: repo.config)["worktree-w"] == "master")
        }
    }

    /// The distinction the whole item rests on. `ccc base <ref> <branch>`
    /// records a base for a worktree cut **by hand**; reading that as
    /// ownership would let `ccc rm` delete a tree ccc never made.
    @Test func aRecordedBaseIsNotAClaimOfOwnership() throws {
        try withRepo { repo in
            let byHand = repo.root.appending(path: ".claude/worktrees/h").path
            try FileManager.default.createDirectory(atPath: repo.root.appending(path: ".claude/worktrees").path,
                                                    withIntermediateDirectories: true)
            try repo.git("worktree", "add", "-q", "-b", "worktree-h", byHand, "master")
            try WorktreeProbe.recordBase("master", for: "worktree-h", repo: repo.path)
            #expect(WorktreeProbe.recordedBases(in: repo.config)["worktree-h"] == "master")
            #expect(WorktreeProbe.cut(at: byHand) == nil)
        }
    }

    @Test func theMainCheckoutAndAPlainFolderAreNeverCut() throws {
        try withRepo { repo in
            #expect(WorktreeProbe.cut(at: repo.path) == nil)
            #expect(WorktreeProbe.cut(at: NSTemporaryDirectory()) == nil)
        }
    }

    /// The record names a path, not a bare `true`, so a branch whose tree
    /// has been replaced under it is no longer ccc's to remove.
    @Test func aRecordThatNamesAnotherTreeIsNotThisOne() throws {
        try withRepo { repo in
            let made = try WorktreeProbe.createWorktree(named: "w", base: "master", repo: repo.path)
            try WorktreeProbe.recordCut("/somewhere/else", for: made.branch, repo: repo.path)
            #expect(WorktreeProbe.cut(at: made.path) == nil)
        }
    }

    /// A session's cwd is often deeper than the worktree's root; the tree
    /// that gets removed is still the root.
    @Test func aFolderInsideTheTreeResolvesToTheTree() throws {
        try withRepo { repo in
            let made = try WorktreeProbe.createWorktree(named: "w", base: "master", repo: repo.path)
            let deep = made.path + "/sub/dir"
            try FileManager.default.createDirectory(atPath: deep, withIntermediateDirectories: true)
            #expect(WorktreeProbe.cut(at: deep)?.path == made.path)
            #expect(WorktreeProbe.cut(at: deep)?.branch == "worktree-w")
            #expect(WorktreeProbe.cut(at: deep)?.repo == repo.path)
        }
    }

    // MARK: the cleanup

    @Test func aCleanTreeAndItsBranchBothGo() throws {
        try withRepo { repo in
            let made = try WorktreeProbe.createWorktree(named: "w", base: "master", repo: repo.path)
            let cut = try #require(WorktreeProbe.cut(at: made.path))
            let cleanup = WorktreeProbe.removeCut(cut)
            #expect(cleanup.removed)
            #expect(cleanup.branchDeleted)
            #expect(!FileManager.default.fileExists(atPath: made.path))
            #expect(try !repo.listed().contains(made.path))
            #expect(try !repo.branches().contains("worktree-w"))
            // Both records go with the branch.
            #expect(WorktreeProbe.recordedCuts(in: repo.config)["worktree-w"] == nil)
            #expect(WorktreeProbe.recordedBases(in: repo.config)["worktree-w"] == nil)
        }
    }

    /// git's refusal is the guard: an untracked file is uncommitted work,
    /// and the tree stays whole — the same answer the harness gives for a
    /// worktree of its own.
    @Test func aDirtyTreeIsKeptAndSaysWhy() throws {
        try withRepo { repo in
            let made = try WorktreeProbe.createWorktree(named: "w", base: "master", repo: repo.path)
            try "not committed\n".write(to: URL(filePath: made.path + "/scratch.txt"), atomically: true, encoding: .utf8)
            let cut = try #require(WorktreeProbe.cut(at: made.path))
            let cleanup = WorktreeProbe.removeCut(cut)
            #expect(!cleanup.removed)
            #expect(!cleanup.branchDeleted)
            #expect(cleanup.said.contains("kept"))
            #expect(FileManager.default.fileExists(atPath: made.path))
            #expect(try repo.branches().contains("worktree-w"))
            // Kept means kept: the mark survives, so a later `ccc rm` —
            // or the same one after a commit — still knows the tree is ours.
            #expect(WorktreeProbe.recordedCuts(in: repo.config)["worktree-w"] == made.path)
        }
    }

    /// Work that is committed but not merged: the tree goes (nothing in it
    /// is unsaved), the branch stays, because `git branch -d` refuses it.
    /// Nothing is lost, and the sentence says both halves.
    @Test func unmergedCommitsKeepTheBranchAfterTheTreeGoes() throws {
        try withRepo { repo in
            let made = try WorktreeProbe.createWorktree(named: "w", base: "master", repo: repo.path)
            let tree = URL(filePath: made.path)
            try "work\n".write(to: tree.appending(path: "b.txt"), atomically: true, encoding: .utf8)
            _ = try Git.run(WorktreeProbe.defaultGit, ["-C", made.path, "add", "b.txt"])
            _ = try Git.run(WorktreeProbe.defaultGit, ["-C", made.path, "commit", "-q", "--no-verify", "-m", "work"])
            let cut = try #require(WorktreeProbe.cut(at: made.path))
            let cleanup = WorktreeProbe.removeCut(cut)
            #expect(cleanup.removed)
            #expect(!cleanup.branchDeleted)
            #expect(!FileManager.default.fileExists(atPath: made.path))
            #expect(try repo.branches().contains("worktree-w"))
            #expect(cleanup.said.contains("kept the branch"))
            #expect(cleanup.said.contains("not in master"))
            // The tree the record named is gone, so the record goes; the
            // base stays with the branch that outlived it.
            #expect(WorktreeProbe.recordedCuts(in: repo.config)["worktree-w"] == nil)
            #expect(WorktreeProbe.recordedBases(in: repo.config)["worktree-w"] == "master")
        }
    }

    /// A branch whose work has landed is deletable, and the whole thing
    /// goes — the ordinary end of a worker that merged.
    @Test func mergedWorkLeavesNothingBehind() throws {
        try withRepo { repo in
            let made = try WorktreeProbe.createWorktree(named: "w", base: "master", repo: repo.path)
            try "work\n".write(to: URL(filePath: made.path + "/b.txt"), atomically: true, encoding: .utf8)
            _ = try Git.run(WorktreeProbe.defaultGit, ["-C", made.path, "add", "b.txt"])
            _ = try Git.run(WorktreeProbe.defaultGit, ["-C", made.path, "commit", "-q", "--no-verify", "-m", "work"])
            try repo.git("merge", "-q", "--no-edit", "worktree-w")
            let cut = try #require(WorktreeProbe.cut(at: made.path))
            let cleanup = WorktreeProbe.removeCut(cut)
            #expect(cleanup.removed)
            #expect(cleanup.branchDeleted)
            #expect(try !repo.branches().contains("worktree-w"))
        }
    }

    /// The regression the first real fixture caught (2026-09-06): a
    /// worktree cut off `trunk` while the main checkout sat on `master`.
    /// The branch had **no commits of its own**, and `git branch -d` — which
    /// measures against the current HEAD — called it "not fully merged"
    /// and kept it. Item 18's whole point is that the base is often not
    /// the default branch, so the base is the ref the work is measured
    /// against.
    @Test func aBranchOffANonDefaultBaseIsMeasuredAgainstThatBase() throws {
        try withRepo { repo in
            try repo.git("checkout", "-q", "-b", "trunk")
            try repo.write("t.txt", "trunk\n")
            try repo.git("add", "t.txt")
            try repo.git("commit", "-q", "--no-verify", "-m", "trunk work")
            try repo.git("checkout", "-q", "master")
            let made = try WorktreeProbe.createWorktree(named: "w", base: "trunk", repo: repo.path)
            let cut = try #require(WorktreeProbe.cut(at: made.path))
            #expect(cut.base == "trunk")
            let cleanup = WorktreeProbe.removeCut(cut)
            #expect(cleanup.removed)
            #expect(cleanup.branchDeleted)
            #expect(try !repo.branches().contains("worktree-w"))
        }
    }

    /// Landed on its base and nowhere near the default branch: still gone.
    @Test func workMergedIntoItsBaseRetiresTheBranch() throws {
        try withRepo { repo in
            try repo.git("checkout", "-q", "-b", "trunk")
            try repo.write("t.txt", "trunk\n")
            try repo.git("add", "t.txt")
            try repo.git("commit", "-q", "--no-verify", "-m", "trunk work")
            try repo.git("checkout", "-q", "master")
            let made = try WorktreeProbe.createWorktree(named: "w", base: "trunk", repo: repo.path)
            try "work\n".write(to: URL(filePath: made.path + "/b.txt"), atomically: true, encoding: .utf8)
            _ = try Git.run(WorktreeProbe.defaultGit, ["-C", made.path, "add", "b.txt"])
            _ = try Git.run(WorktreeProbe.defaultGit, ["-C", made.path, "commit", "-q", "--no-verify", "-m", "work"])
            // Land it on trunk, which is not checked out anywhere.
            try repo.git("fetch", "-q", ".", "worktree-w:trunk")
            let cleanup = WorktreeProbe.removeCut(try #require(WorktreeProbe.cut(at: made.path)))
            #expect(cleanup.branchDeleted)
            #expect(try !repo.branches().contains("worktree-w"))
        }
    }

    /// Unmerged but pushed: the harness's own second word is "unpushed",
    /// and work that is on origin is not work that can be lost here.
    @Test func unmergedButPushedRetiresTheBranch() throws {
        try withRepo { repo in
            let origin = repo.root.deletingLastPathComponent().appending(path: "origin-\(UUID().uuidString).git")
            defer { try? FileManager.default.removeItem(at: origin) }
            _ = try Git.run(WorktreeProbe.defaultGit, ["init", "-q", "--bare", origin.path])
            try repo.git("remote", "add", "origin", origin.path)
            let made = try WorktreeProbe.createWorktree(named: "w", base: "master", repo: repo.path)
            try "work\n".write(to: URL(filePath: made.path + "/b.txt"), atomically: true, encoding: .utf8)
            _ = try Git.run(WorktreeProbe.defaultGit, ["-C", made.path, "add", "b.txt"])
            _ = try Git.run(WorktreeProbe.defaultGit, ["-C", made.path, "commit", "-q", "--no-verify", "-m", "work"])
            _ = try Git.run(WorktreeProbe.defaultGit, ["-C", made.path, "push", "-q", "origin", "worktree-w"])
            let cleanup = WorktreeProbe.removeCut(try #require(WorktreeProbe.cut(at: made.path)))
            #expect(cleanup.removed)
            #expect(cleanup.branchDeleted)
            #expect(try !repo.branches().contains("worktree-w"))
        }
    }

    // MARK: the config parser both keys share

    @Test func theParserReadsOneKeyPerBranchSection() {
        let config = """
        [core]
        \trepositoryformatversion = 0
        [branch "worktree-a"]
        \tccc-base = storefront
        \tccc-cut = /r/.claude/worktrees/a
        [branch "worktree-b"]
        \tvscode-merge-base = origin/main
        \t# ccc-cut = /never
        [remote "origin"]
        \tccc-cut = /not-a-branch
        """
        #expect(WorktreeProbe.recordedCuts(in: config) == ["worktree-a": "/r/.claude/worktrees/a"])
        #expect(WorktreeProbe.recordedBases(in: config) == ["worktree-a": "storefront", "worktree-b": "main"])
    }
}
