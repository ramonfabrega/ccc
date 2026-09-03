import Foundation

/// What git says about a session's folder when it is a worktree: the
/// branch, the repository's default branch, and how the two stand.
/// Joined where the filesystem is, like the model column, and carried
/// across the hop in the far side's `ccc list --json` row (nil off an
/// older ccc). The row shows it; the merge verb acts on a fresh reading.
public struct WorktreeInfo: Codable, Sendable, Equatable {
    /// The worktree's branch (`worktree-v2`). A detached worktree has no
    /// row info at all: there is nothing to merge by name.
    public var branch: String
    /// The branch it is measured against and merges into — the repo's
    /// default branch, *local* (`master`, `main`): the nightly
    /// fast-forward is a local act, and `origin/master` may lag it.
    public var base: String
    /// Commits on `branch` that `base` lacks — what a merge would bring.
    public var ahead: Int
    /// Commits on `base` that `branch` lacks — what makes a fast-forward
    /// impossible.
    public var behind: Int
    /// The main checkout, where the merge runs.
    public var repo: String

    public init(branch: String, base: String, ahead: Int, behind: Int, repo: String) {
        self.branch = branch
        self.base = base
        self.ahead = ahead
        self.behind = behind
        self.repo = repo
    }

    /// `base` can take `branch` without a merge commit.
    public var canFastForward: Bool { ahead > 0 && behind == 0 }
    /// There is something to bring over at all.
    public var hasWork: Bool { ahead > 0 }

    /// "worktree-v2 ↑3", "worktree-v2 ↑3 ↓2", "worktree-v2 level".
    public var summary: String {
        var out = branch
        if ahead > 0 { out += " ↑\(ahead)" }
        if behind > 0 { out += " ↓\(behind)" }
        if ahead == 0 && behind == 0 { out += " level" }
        return out
    }
}

/// Reads `WorktreeInfo` for a folder, spawning `git` only when a ref
/// moved. The poll is 2 s and a roster has twenty rows, so a git process
/// per row per tick is the wrong shape; instead the worktree's HEAD and
/// the base's tip are read as files (`.git/worktrees/<n>/HEAD`,
/// `refs/heads/<b>`, `packed-refs`), and `rev-list --count` runs once per
/// distinct pair of shas. Steady state: zero processes. Every read is
/// read-only and lenient — a folder that is not a worktree, or a git
/// layout this does not understand, is `nil`, never an error.
public final class WorktreeProbe: @unchecked Sendable {
    private struct Entry {
        var key: String   // "<branch sha>/<base sha>"
        var info: WorktreeInfo
    }

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    /// Per repository: the default branch, found once.
    private var bases: [String: String] = [:]
    public private(set) var spawns = 0
    public let git: String

    public init(git: String = WorktreeProbe.defaultGit) {
        self.git = git
    }

    public static let defaultGit = "/usr/bin/git"

    /// The layout of one worktree, from its files alone.
    public struct Layout: Equatable, Sendable {
        /// `<repo>/.git/worktrees/<name>`
        public var gitdir: String
        /// `<repo>/.git`
        public var commonDir: String
        /// `<repo>`
        public var repo: String
        /// `refs/heads/<branch>` target of the worktree's HEAD, or nil when
        /// detached.
        public var branch: String?
    }

    /// `cwd` or an ancestor whose `.git` is a *file* (`gitdir: …`) — the
    /// mark of a linked worktree. Walks up so a session deep in a
    /// worktree's tree still resolves.
    public static func layout(of cwd: String) -> Layout? {
        var dir = URL(filePath: cwd).standardizedFileURL
        while true {
            let dotGit = dir.appending(path: ".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                guard !isDirectory.boolValue else { return nil }   // a main checkout, not a worktree
                guard let text = try? String(contentsOf: dotGit, encoding: .utf8),
                      let line = text.split(separator: "\n").first, line.hasPrefix("gitdir:") else { return nil }
                let gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                // Directory hints matter: a relative `commondir` (`../..`)
                // resolved against a base with no trailing slash lands one
                // level too high — `/x` for `/x/.git` — and the repo becomes
                // `/`. Found on the first real `ccc list`, every row nil.
                let gitdirURL = URL(filePath: gitdir, directoryHint: .isDirectory, relativeTo: dir).standardizedFileURL
                let common = (try? String(contentsOf: gitdirURL.appending(path: "commondir"), encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !common.isEmpty else { return nil }
                let commonURL = URL(filePath: common, directoryHint: .isDirectory, relativeTo: gitdirURL).standardizedFileURL
                let head = (try? String(contentsOf: gitdirURL.appending(path: "HEAD"), encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let branch = head.hasPrefix("ref: refs/heads/") ? String(head.dropFirst("ref: refs/heads/".count)) : nil
                return Layout(gitdir: gitdirURL.path, commonDir: commonURL.path,
                              repo: commonURL.deletingLastPathComponent().path, branch: branch)
            }
            let parent = dir.deletingLastPathComponent()
            guard parent.path != dir.path, dir.path != "/" else { return nil }
            dir = parent
        }
    }

    /// The sha a local branch points at: the loose ref, else `packed-refs`.
    public static func sha(of branch: String, commonDir: String) -> String? {
        let loose = URL(filePath: commonDir).appending(path: "refs/heads/\(branch)")
        if let text = try? String(contentsOf: loose, encoding: .utf8) {
            let sha = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if sha.count == 40 { return sha }
        }
        guard let packed = try? String(contentsOf: URL(filePath: commonDir).appending(path: "packed-refs"), encoding: .utf8) else { return nil }
        let want = "refs/heads/\(branch)"
        for line in packed.split(separator: "\n") where !line.hasPrefix("#") && !line.hasPrefix("^") {
            let parts = line.split(separator: " ", maxSplits: 1)
            if parts.count == 2, parts[1] == want { return String(parts[0]) }
        }
        return nil
    }

    /// The repository's default branch, local: what `origin/HEAD` names
    /// when that branch exists here, else `master`, else `main`. Nil when
    /// none of them exists, which is a repo this cannot merge into.
    public static func defaultBranch(commonDir: String) -> String? {
        var candidates: [String] = []
        if let text = try? String(contentsOf: URL(filePath: commonDir).appending(path: "refs/remotes/origin/HEAD"), encoding: .utf8) {
            let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = "ref: refs/remotes/origin/"
            if line.hasPrefix(prefix) { candidates.append(String(line.dropFirst(prefix.count))) }
        }
        candidates += ["master", "main"]
        return candidates.first { sha(of: $0, commonDir: commonDir) != nil }
    }

    /// The reading for a folder, from the cache when neither sha moved.
    public func info(forCwd cwd: String) -> WorktreeInfo? {
        guard let layout = Self.layout(of: cwd), let branch = layout.branch else { return nil }
        let base: String
        lock.lock()
        if let known = bases[layout.repo] {
            base = known
        } else {
            guard let found = Self.defaultBranch(commonDir: layout.commonDir) else { lock.unlock(); return nil }
            bases[layout.repo] = found
            base = found
        }
        lock.unlock()
        guard branch != base else { return nil }   // a worktree on master itself has nothing to land
        guard let branchSHA = Self.sha(of: branch, commonDir: layout.commonDir),
              let baseSHA = Self.sha(of: base, commonDir: layout.commonDir) else { return nil }
        let key = "\(branchSHA)/\(baseSHA)"
        lock.lock()
        if let entry = cache[cwd], entry.key == key {
            lock.unlock()
            return entry.info
        }
        lock.unlock()
        guard let (ahead, behind) = count(base: base, branch: branch, in: layout.repo) else { return nil }
        let info = WorktreeInfo(branch: branch, base: base, ahead: ahead, behind: behind, repo: layout.repo)
        lock.lock()
        cache[cwd] = Entry(key: key, info: info)
        lock.unlock()
        return info
    }

    /// Always a fresh count — what the merge verb reads before acting.
    public func fresh(forCwd cwd: String) -> WorktreeInfo? {
        lock.lock()
        cache[cwd] = nil
        lock.unlock()
        return info(forCwd: cwd)
    }

    /// `git rev-list --left-right --count base...branch` → (ahead, behind).
    private func count(base: String, branch: String, in repo: String) -> (Int, Int)? {
        lock.lock(); spawns += 1; lock.unlock()
        guard let out = try? Git.run(git, ["-C", repo, "rev-list", "--left-right", "--count",
                                          "refs/heads/\(base)...refs/heads/\(branch)"]).stdout else { return nil }
        let parts = out.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, let behind = Int(parts[0]), let ahead = Int(parts[1]) else { return nil }
        return (ahead, behind)
    }
}

/// How a worktree's branch lands on the default branch. The words are
/// git's own so nothing new has to be learned: `--ff-only` is the nightly
/// move and the default, `--no-ff` the merge commit when master moved,
/// `--squash` one commit for a branch that is finished. Rebase is not
/// offered: it rewrites the branch under a session that may still be
/// committing to it.
public enum MergeStrategy: String, CaseIterable, Codable, Sendable {
    case ffOnly = "ff-only"
    case noFF = "no-ff"
    case squash

    public var flag: String { "--\(rawValue)" }

    public static func parse(flag: String) -> MergeStrategy? {
        allCases.first { $0.flag == flag }
    }

    /// The menu's word.
    public var label: String {
        switch self {
        case .ffOnly: return "Fast-forward"
        case .noFF: return "Merge"
        case .squash: return "Squash"
        }
    }
}

public struct MergeOutcome: Sendable, Equatable {
    public var merged: Bool
    /// One sentence: what happened, or why it did not.
    public var said: String
}

/// The merge itself, in the main checkout, with the guards that make it
/// unable to lose work: the checkout must be on the base branch and
/// clean, a fast-forward must be possible when that is what was asked,
/// and a conflict backs out to where it started. Conflicts are a
/// terminal's job, never a menu's.
public enum GitMerge {
    public static func perform(_ strategy: MergeStrategy, on info: WorktreeInfo,
                               git: String = WorktreeProbe.defaultGit) -> MergeOutcome {
        let repo = info.repo
        func g(_ args: [String]) throws -> Git.Result { try Git.run(git, ["-C", repo] + args) }
        let name = "\(info.branch) → \(info.base)"
        guard info.hasWork else {
            return MergeOutcome(merged: false, said: "nothing to merge: \(info.branch) has no commits \(info.base) lacks")
        }
        guard let head = try? g(["symbolic-ref", "--short", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return MergeOutcome(merged: false, said: "\(repo) is not on a branch; refusing to merge")
        }
        guard head == info.base else {
            return MergeOutcome(merged: false, said: "\(repo) is on \(head), not \(info.base); refusing to merge")
        }
        if let status = try? g(["status", "--porcelain", "--untracked-files=no"]).stdout, !status.isEmpty {
            let n = status.split(separator: "\n").count
            return MergeOutcome(merged: false, said: "\(repo) has \(n) uncommitted change\(n == 1 ? "" : "s"); refusing to merge")
        }
        let plural = "\(info.ahead) commit\(info.ahead == 1 ? "" : "s")"
        switch strategy {
        case .ffOnly:
            guard info.behind == 0 else {
                return MergeOutcome(merged: false, said: "\(info.base) has moved \(info.behind) commit\(info.behind == 1 ? "" : "s") past \(info.branch); a fast-forward is not possible — merge or squash instead")
            }
            do {
                _ = try g(["merge", "--ff-only", info.branch])
                let sha = (try? g(["rev-parse", "--short", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
                return MergeOutcome(merged: true, said: "fast-forwarded \(name) (\(plural), now \(sha))")
            } catch {
                return MergeOutcome(merged: false, said: "fast-forward \(name) failed: \(Self.trim(error))")
            }
        case .noFF:
            do {
                _ = try g(["merge", "--no-ff", "--no-edit", "-m", "Merge \(info.branch) (\(plural))", info.branch])
                let sha = (try? g(["rev-parse", "--short", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
                return MergeOutcome(merged: true, said: "merged \(name) (\(plural), merge commit \(sha))")
            } catch {
                let conflicts = conflictedFiles(g)
                _ = try? g(["merge", "--abort"])
                return MergeOutcome(merged: false, said: "merge \(name) conflicts in \(conflicts); backed out, \(info.base) untouched")
            }
        case .squash:
            let subjects = (try? g(["log", "--format=%s", "\(info.base)..\(info.branch)"]).stdout)?
                .split(separator: "\n").map(String.init) ?? []
            do {
                _ = try g(["merge", "--squash", info.branch])
            } catch {
                let conflicts = conflictedFiles(g)
                _ = try? g(["reset", "--merge"])
                return MergeOutcome(merged: false, said: "squash \(name) conflicts in \(conflicts); backed out, \(info.base) untouched")
            }
            var message = "Squash \(info.branch) (\(plural))"
            if !subjects.isEmpty { message += "\n\n" + subjects.map { "- \($0)" }.joined(separator: "\n") }
            do {
                _ = try g(["commit", "--no-verify", "-m", message])
                let sha = (try? g(["rev-parse", "--short", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
                return MergeOutcome(merged: true, said: "squashed \(name) (\(plural) → \(sha)); \(info.branch) is done — a second squash would re-apply the same diff")
            } catch {
                _ = try? g(["reset", "--merge"])
                return MergeOutcome(merged: false, said: "squash \(name): commit failed (\(Self.trim(error))); backed out")
            }
        }
    }

    private static func conflictedFiles(_ g: ([String]) throws -> Git.Result) -> String {
        let files = (try? g(["diff", "--name-only", "--diff-filter=U"]).stdout)?
            .split(separator: "\n").map(String.init) ?? []
        if files.isEmpty { return "the working tree" }
        return files.prefix(4).joined(separator: ", ") + (files.count > 4 ? " (+\(files.count - 4))" : "")
    }

    private static func trim(_ error: Error) -> String {
        "\(error)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// `git` as a subprocess: stdout and stderr to EOF, a non-zero exit as an
/// error carrying stderr. Synchronous; every caller is already off the
/// main actor or is the CLI.
public enum Git {
    public struct Result: Sendable {
        public var stdout: String
        public var stderr: String
    }

    public struct Failure: Error, CustomStringConvertible {
        public var status: Int32
        public var stderr: String
        public var description: String {
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "git exited \(status)" : detail
        }
    }

    public static func run(_ git: String, _ args: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(filePath: git)
        process.arguments = args
        // Never a prompt, never a pager, never an editor: a merge that
        // stops to ask would hang a poll or a click.
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_PAGER"] = "cat"
        env["GIT_EDITOR"] = "true"
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let result = Result(stdout: String(decoding: stdout, as: UTF8.self), stderr: String(decoding: stderr, as: UTF8.self))
        guard process.terminationStatus == 0 else {
            throw Failure(status: process.terminationStatus, stderr: result.stderr + result.stdout)
        }
        return result
    }
}

extension ClaudeCLI {
    /// `ccc merge <id> --<strategy>` on a remote host: the merge runs where
    /// the repository is, by the far side's own ccc. Needs `ccc` there.
    public func mergeArgv(_ strategy: MergeStrategy, id: String) -> [String]? {
        guard let ccc = host.ccc, let destination = host.ssh else { return nil }
        return sshPrefix(tty: false, destination: destination) + [ccc, "merge", id, strategy.flag]
    }

    /// Land a session's worktree branch on the repository's default
    /// branch. Local: the row's cwd from one roster read, a fresh count,
    /// then `GitMerge`. Remote: the same verb on the far side, its answer
    /// passed through. Either way one sentence comes back, and `merged`
    /// says whether anything changed.
    public func merge(_ strategy: MergeStrategy, id: String, probe: WorktreeProbe = WorktreeProbe()) async throws -> MergeOutcome {
        if host.isLocal {
            let roster = RosterDecoder.decode(try await agentsJSON())
            guard let row = roster.sessions.first(where: { $0.id == id }) else {
                throw MergeError.noSuchSession(id)
            }
            guard let info = probe.fresh(forCwd: row.cwd) else {
                throw MergeError.notAWorktree(id, row.cwd)
            }
            return await Task.detached(priority: .userInitiated) { GitMerge.perform(strategy, on: info, git: probe.git) }.value
        }
        guard let argv = mergeArgv(strategy, id: id) else { throw MergeError.noRemoteCCC(host.name) }
        try prepareControlDirectory()
        let result = try await run(argv, accepting: [0, 1], program: "ccc")
        let said = (String(decoding: result.stdout, as: UTF8.self) + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        return MergeOutcome(merged: result.status == 0, said: said)
    }

    public enum MergeError: Error, CustomStringConvertible {
        case noSuchSession(String)
        case notAWorktree(String, String)
        case noRemoteCCC(String)
        public var description: String {
            switch self {
            case .noSuchSession(let id): return "no session '\(id)' in the roster"
            case .notAWorktree(let id, let cwd): return "\(id) is not in a worktree on a branch (\(cwd))"
            case .noRemoteCCC(let host): return "the merge runs where the repository is, and \(host) has no ccc for it (`ccc hosts add \(host)` finds one)"
            }
        }
    }
}
