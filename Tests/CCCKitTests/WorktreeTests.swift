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
            #expect(level == WorktreeInfo(branch: "worktree-t", base: "master", ahead: 0, behind: 0,
                                          repo: repo.root.standardizedFileURL.path))
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
                #expect(!outcome.merged && outcome.said.contains("1 uncommitted change"))
            }
            #expect(try repo.git("rev-parse", "master") == before)
            #expect(try repo.git("status", "--porcelain", "--untracked-files=no").contains("M a.txt"))
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
            let info = try #require(WorktreeProbe().fresh(forCwd: repo.wt))
            for strategy in [MergeStrategy.noFF, .squash] {
                let outcome = GitMerge.perform(strategy, on: info)
                #expect(!outcome.merged, "\(outcome.said)")
                #expect(outcome.said.contains("conflicts in a.txt") && outcome.said.contains("backed out"))
                #expect(try repo.git("rev-parse", "master") == before)
                #expect(try repo.git("status", "--porcelain", "--untracked-files=no") == "")
                #expect(try String(contentsOf: repo.root.appending(path: "a.txt"), encoding: .utf8) == "ours\n")
            }
        }
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
        if case .shell(let ref) = back { #expect(ref == SessionRef(host: "studio", id: "a1b2")) } else { Issue.record("not shell") }
        let close = try JSONDecoder().decode(ControlRequest.self, from: JSONEncoder().encode(ControlRequest.shellClose))
        if case .shellClose = close {} else { Issue.record("not shellClose") }
    }
}
