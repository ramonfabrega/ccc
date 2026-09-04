import Foundation
import Testing

@testable import CCCKit

/// Item 18: the base a worktree branch is measured against is no longer
/// always the default branch. Two consumers in one day kept their trunk
/// on a branch (`storefront`, 590 ahead of master; `worktree-replan-pdb`,
/// eight ahead of main) and the column, `merge`, `update` and `pull` all
/// pointed at the branch nobody lands on. A base can be recorded per
/// worktree branch in the repo's own config, `ccc spawn` records it when
/// it cuts a worktree, and `ccc base` is the read and the write by hand.
@Suite(.serialized) struct BaseTests {
    private struct Repo {
        let root: URL
        let worktree: URL
        var wt: String { worktree.path }
        func git(_ args: String..., in dir: URL? = nil) throws -> String {
            try Git.run(WorktreeProbe.defaultGit, ["-C", (dir ?? root).path] + args).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func commit(_ file: String, _ text: String, message: String, in dir: URL? = nil) throws {
            let dir = dir ?? root
            try text.write(to: dir.appending(path: file), atomically: true, encoding: .utf8)
            _ = try git("add", file, in: dir)
            _ = try git("commit", "-q", "--no-verify", "-m", message, in: dir)
        }
    }

    /// master with one commit; `trunk` one commit past it; a worktree on
    /// `worktree-t` cut off trunk's tip — the storefront shape in small.
    private func withRepo(_ body: (Repo) throws -> Void) throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-base-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = Repo(root: root, worktree: root.appending(path: ".claude/worktrees/t"))
        _ = try repo.git("init", "-q", "-b", "master")
        _ = try repo.git("config", "user.email", "t@example.com")
        _ = try repo.git("config", "user.name", "t")
        try repo.commit("a.txt", "one\n", message: "first")
        _ = try repo.git("checkout", "-q", "-b", "trunk")
        try repo.commit("b.txt", "two\n", message: "trunk work")
        _ = try repo.git("checkout", "-q", "master")
        try FileManager.default.createDirectory(at: root.appending(path: ".claude"), withIntermediateDirectories: true)
        _ = try repo.git("worktree", "add", "-q", "-b", "worktree-t", repo.wt, "trunk")
        try body(repo)
    }

    @Test func theConfigIsReadForOurKeyAndVSCodes() {
        let config = """
        [core]
        \trepositoryformatversion = 0
        [branch "master"]
        \tremote = origin
        \tvscode-merge-base = origin/master
        [branch "worktree-a"]
        \tccc-base = storefront
        \tvscode-merge-base = origin/master
        [branch "worktree-b"]
        \tvscode-merge-base = origin/expo-52
        [branch "worktree-c"]
        \tremote = origin
        # a comment
        """
        let bases = WorktreeProbe.recordedBases(in: config)
        #expect(bases["worktree-a"] == "storefront", "ours wins where both exist")
        #expect(bases["worktree-b"] == "expo-52", "VS Code's, with origin/ taken off")
        #expect(bases["worktree-c"] == nil)
        #expect(bases["master"] == "master")
        #expect(WorktreeProbe.recordedBases(in: "").isEmpty)
    }

    /// Without a record the worktree is measured against master and reads
    /// one ahead — the wrong number storefront-launch reported, in small.
    /// Recorded against trunk it is level, and the column says so.
    @Test func aRecordedBaseReplacesTheDefault() throws {
        try withRepo { repo in
            let probe = WorktreeProbe()
            let wrong = try #require(probe.info(forCwd: repo.wt))
            #expect(wrong.base == "master" && wrong.ahead == 1 && wrong.behind == 0)
            #expect(wrong.baseRecorded == false)

            try WorktreeProbe.recordBase("trunk", for: "worktree-t", repo: repo.root.path)
            let right = try #require(probe.info(forCwd: repo.wt))
            #expect(right.base == "trunk" && right.ahead == 0 && right.behind == 0)
            #expect(right.baseRecorded == true)
            #expect(right.summary == "worktree-t level")

            // Forgotten, it is the default again; forgetting twice is fine.
            try WorktreeProbe.recordBase(nil, for: "worktree-t", repo: repo.root.path)
            try WorktreeProbe.recordBase(nil, for: "worktree-t", repo: repo.root.path)
            #expect(probe.info(forCwd: repo.wt)?.base == "master")

            // A recorded base that does not resolve is ignored, not obeyed.
            try WorktreeProbe.recordBase("gone", for: "worktree-t", repo: repo.root.path)
            #expect(probe.info(forCwd: repo.wt)?.base == "master")
        }
    }

    @Test func theCheckoutIsFoundFromEitherSide() throws {
        try withRepo { repo in
            let root = try #require(WorktreeProbe.checkout(of: repo.root.path))
            #expect(root.branch == "master")
            #expect(root.repo == repo.root.standardizedFileURL.path)
            let deep = try #require(WorktreeProbe.checkout(of: repo.wt + "/Sources"))
            #expect(deep.branch == "worktree-t")
            #expect(deep.repo == repo.root.standardizedFileURL.path)
            #expect(WorktreeProbe.checkout(of: NSTemporaryDirectory()) == nil)
        }
    }

    @Test func aWorktreeIsCutOffTheBaseAndRecorded() throws {
        try withRepo { repo in
            let made = try WorktreeProbe.createWorktree(named: "w2", base: "trunk", repo: repo.root.path)
            #expect(made.branch == "worktree-w2" && made.base == "trunk")
            #expect(made.path == repo.root.path + "/.claude/worktrees/w2")
            let info = try #require(WorktreeProbe().info(forCwd: made.path))
            #expect(info.base == "trunk" && info.baseRecorded == true && info.ahead == 0)
            // The layout is the harness's own, so `claude rm`'s guard and
            // the roster's reading both apply.
            #expect(WorktreeProbe.layout(of: made.path)?.branch == "worktree-w2")
            // Refusals: a base that does not exist, a name a shell would mind, a path taken.
            #expect(throws: SpawnError.self) { try WorktreeProbe.createWorktree(named: "w3", base: "nope", repo: repo.root.path) }
            #expect(throws: SpawnError.self) { try WorktreeProbe.createWorktree(named: "w 3", base: "trunk", repo: repo.root.path) }
            #expect(throws: SpawnError.self) { try WorktreeProbe.createWorktree(named: "w2", base: "trunk", repo: repo.root.path) }
        }
    }

    @Test func worktreeNamesAreSafe() {
        #expect(WorktreeProbe.worktreeName(from: "Storefront Launch") == "storefront-launch")
        #expect(WorktreeProbe.worktreeName(from: "att/audit: level 2") == "att-audit-level-2")
        #expect(WorktreeProbe.worktreeName(from: "!!!") == nil)
        #expect(WorktreeProbe.worktreeName(from: "ok") == "ok")
    }

    /// The spawn's half. From a folder on the default branch with no base
    /// named, the request is untouched and the harness cuts the worktree.
    /// From a folder on any other branch — the spawning session's own
    /// worktree, which is every reporter's case — ccc cuts it off that
    /// branch and hands the harness a plain cwd. A named base wins.
    @Test func theSpawnCutsOffTheAskersBranch() throws {
        try withRepo { repo in
            let cli = ClaudeCLI(executable: "/usr/bin/true", host: .local)
            var plain = SpawnRequest(cwd: repo.root.path, prompt: "go", worktree: "")
            #expect(try cli.prepareWorktree(&plain) == nil)
            #expect(plain.worktree == "" && plain.cwd == repo.root.path)

            var fromWorktree = SpawnRequest(cwd: repo.wt, prompt: "go", name: "Wave One", worktree: "")
            let made = try #require(try cli.prepareWorktree(&fromWorktree))
            #expect(made.base == "worktree-t" && made.branch == "worktree-wave-one")
            #expect(fromWorktree.worktree == nil && fromWorktree.cwd == made.path)
            #expect(WorktreeProbe().info(forCwd: made.path)?.base == "worktree-t")

            var named = SpawnRequest(cwd: repo.root.path, prompt: "go", worktree: "off-trunk", base: "trunk")
            let cut = try #require(try cli.prepareWorktree(&named))
            #expect(cut.base == "trunk" && cut.branch == "worktree-off-trunk")

            var nothing = SpawnRequest(cwd: repo.root.path, prompt: "go")
            #expect(try cli.prepareWorktree(&nothing) == nil)
        }
    }

    /// `--base` on a remote host is refused with the way out named; a bare
    /// `--worktree` there is the harness's, as before.
    @Test func aRemoteBaseIsRefusedNotSilentlyDropped() throws {
        let remote = ClaudeCLI(executable: "~/.local/bin/claude",
                               host: Host(name: "studio", ssh: "studio", claude: "~/.local/bin/claude"))
        var request = SpawnRequest(cwd: "~/code/app", prompt: "go", worktree: "", base: "trunk")
        #expect(throws: SpawnError.self) { try remote.prepareWorktree(&request) }
        var bare = SpawnRequest(cwd: "~/code/app", prompt: "go", worktree: "")
        #expect(try remote.prepareWorktree(&bare) == nil)
        #expect(bare.worktree == "")
    }
}
