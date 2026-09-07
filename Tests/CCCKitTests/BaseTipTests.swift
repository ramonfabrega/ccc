import Foundation
import Testing

@testable import CCCKit

/// Item 20: which tip of the base `↓N` counts and `ccc update` merges.
///
/// The fixture is the fleet's own shape, which a lone repository never
/// makes: a **commander's worktree holds the base branch checked out**,
/// and workers branch off it. Reproduced from 2026-09-06, when a worker's
/// `git merge --no-edit origin/worktree-replan-pdb` was refused by the
/// auto-mode permission classifier and the question came back as "is
/// `ccc update` the verb briefs should say instead".
@Suite(.serialized) struct BaseTipTests {
    /// origin.git ← repo(main) with two worktrees: `cmd` on
    /// `worktree-replan-pdb` (the base), `w` on `loop-219` (the worker).
    private func withFleet(_ body: (URL, URL, URL, (String, URL) throws -> String) throws -> Void) throws {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-tip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let origin = dir.appending(path: "origin.git"), root = dir.appending(path: "repo")
        func git(_ line: String, _ at: URL) throws -> String {
            try Git.run(WorktreeProbe.defaultGit, ["-C", at.path] + line.split(separator: " ").map(String.init)).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = try Git.run(WorktreeProbe.defaultGit, ["init", "-q", "--bare", origin.path])
        _ = try Git.run(WorktreeProbe.defaultGit, ["init", "-q", "-b", "main", root.path])
        _ = try git("config user.email t@example.com", root)
        _ = try git("config user.name t", root)
        try "one\n".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        _ = try git("add a.txt", root)
        _ = try git("commit -q --no-verify -m first", root)
        _ = try git("remote add origin \(origin.path)", root)
        _ = try git("push -q -u origin main", root)
        try FileManager.default.createDirectory(at: root.appending(path: ".claude"), withIntermediateDirectories: true)
        // The commander's tree holds the base branch — the whole point.
        let cmd = root.appending(path: ".claude/worktrees/cmd")
        _ = try git("worktree add -q -b worktree-replan-pdb \(cmd.path) main", root)
        _ = try git("push -q -u origin worktree-replan-pdb", cmd)
        // The worker, cut off the base (which is what `ccc spawn --base` does).
        let w = root.appending(path: ".claude/worktrees/w")
        _ = try git("worktree add -q -b loop-219 \(w.path) worktree-replan-pdb", root)
        _ = try git("config branch.loop-219.ccc-base worktree-replan-pdb", root)
        try body(root, cmd, w, git)
    }

    private func commit(_ name: String, in dir: URL, _ git: (String, URL) throws -> String) throws {
        try "x\n".write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
        _ = try git("add \(name)", dir)
        _ = try git("commit -q --no-verify -m \(name)", dir)
    }

    /// While the commander's local ref and origin agree — which is the
    /// steady state, because the commander pushes as it goes — nothing
    /// changes: the tip is the local branch and the sentences name it.
    @Test func aLevelBaseKeepsTheLocalTip() throws {
        try withFleet { root, cmd, w, git in
            try commit("b.txt", in: cmd, git)
            _ = try git("push -q origin worktree-replan-pdb", cmd)
            let info = try #require(WorktreeProbe().info(forCwd: w.path))
            #expect(info.base == "worktree-replan-pdb")
            #expect(info.baseRecorded == true)
            #expect(info.baseTip == nil)
            #expect(info.baseTipRef == "refs/heads/worktree-replan-pdb")
            #expect(info.behind == 1)
        }
    }

    /// The drift case. The commander's ref stays where it is, origin moves
    /// ahead of it (another Mac pushed, or the ref was fetched and never
    /// merged). **`ccc pull` cannot fix this**: it fast-forwards in the
    /// main checkout and refuses unless `HEAD == base`, and here the main
    /// checkout is on `main` while the base is checked out in the
    /// commander's tree. So the tip follows origin instead, and the column
    /// counts what the verb would actually bring.
    @Test func anOriginAheadOfTheLocalBaseBecomesTheTip() throws {
        try withFleet { root, cmd, w, git in
            // Two commits that reach origin/<base> without moving the
            // commander's checked-out ref: pushed from a clone, fetched here.
            let clone = root.deletingLastPathComponent().appending(path: "clone")
            _ = try Git.run(WorktreeProbe.defaultGit,
                            ["clone", "-q", "-b", "worktree-replan-pdb",
                             root.deletingLastPathComponent().appending(path: "origin.git").path, clone.path])
            _ = try git("config user.email t@example.com", clone)
            _ = try git("config user.name t", clone)
            try commit("c.txt", in: clone, git)
            try commit("d.txt", in: clone, git)
            _ = try git("push -q origin worktree-replan-pdb", clone)
            _ = try git("fetch -q origin", root)

            let info = try #require(WorktreeProbe().info(forCwd: w.path))
            #expect(info.baseUnpulled == 2, "origin holds two commits the local base lacks")
            #expect(info.baseUnpushed == 0, "and the local base holds none origin lacks")
            #expect(info.baseTip == "origin/worktree-replan-pdb")
            #expect(info.baseTipRef == "refs/remotes/origin/worktree-replan-pdb")
            #expect(info.baseTipName == "origin/worktree-replan-pdb")
            // The column counts against the same tip the verb will merge —
            // against the local ref this would have read 0, and `update`
            // would have said "nothing to update" to a worker two commits
            // behind the branch it was told to follow.
            #expect(info.behind == 2)

            // And the verb does what the worker's `git merge origin/<base>`
            // did, naming the tip it used.
            let outcome = GitUpdate.perform(on: info, worktree: w.path)
            #expect(outcome.merged)
            #expect(outcome.said.hasPrefix("fast-forwarded loop-219 to origin/worktree-replan-pdb (2 commits"),
                    "\(outcome.said)")
            #expect(try git("rev-parse HEAD", w) == git("rev-parse refs/remotes/origin/worktree-replan-pdb", root))
            // Nobody else's worktree was written to.
            #expect(try git("rev-parse HEAD", cmd) == git("rev-parse refs/heads/worktree-replan-pdb", root))
        }
    }

    /// A base that has *diverged* from origin stays local. Picking origin
    /// there would merge commits the commander deliberately does not have;
    /// picking local hides commits it does not know about. Neither is
    /// ccc's call, so the ordinary answer stands and the ⇡⇣ marks say why.
    @Test func aDivergedBaseStaysLocal() throws {
        try withFleet { root, cmd, w, git in
            let clone = root.deletingLastPathComponent().appending(path: "clone")
            _ = try Git.run(WorktreeProbe.defaultGit,
                            ["clone", "-q", "-b", "worktree-replan-pdb",
                             root.deletingLastPathComponent().appending(path: "origin.git").path, clone.path])
            _ = try git("config user.email t@example.com", clone)
            _ = try git("config user.name t", clone)
            try commit("c.txt", in: clone, git)
            _ = try git("push -q origin worktree-replan-pdb", clone)
            _ = try git("fetch -q origin", root)
            try commit("e.txt", in: cmd, git)   // the commander moved too

            let info = try #require(WorktreeProbe().info(forCwd: w.path))
            #expect(info.baseUnpulled == 1 && info.baseUnpushed == 1, "diverged")
            #expect(info.baseTip == nil)
            #expect(info.behind == 1, "counted against the local base, as before")
        }
    }
}
