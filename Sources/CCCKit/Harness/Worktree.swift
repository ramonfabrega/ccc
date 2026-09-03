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
    /// Commits on `branch` that are on no `origin/*` ref (slice 2) —
    /// what a push would send, and what makes the harness keep the
    /// worktree on `claude rm`. Nil when the repository has no origin,
    /// where the word means nothing. Exact from local refs, as of the
    /// last fetch or push; never a network call.
    public var unpushed: Int?
    /// `base` ahead of `origin/<base>` by name: a master that was
    /// fast-forwarded here and never pushed is one the other Mac cannot
    /// see, even though every commit is on origin under the branch's
    /// name. Nil when origin has no such branch.
    public var baseUnpushed: Int?

    public init(branch: String, base: String, ahead: Int, behind: Int, repo: String,
                unpushed: Int? = nil, baseUnpushed: Int? = nil) {
        self.branch = branch
        self.base = base
        self.ahead = ahead
        self.behind = behind
        self.repo = repo
        self.unpushed = unpushed
        self.baseUnpushed = baseUnpushed
    }

    /// Lenient on what slice 2 added: a slice-1 ccc on the far side sends
    /// no `unpushed`, and that must not cost the row its branch.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        branch = try c.decode(String.self, forKey: .branch)
        base = try c.decode(String.self, forKey: .base)
        ahead = try c.decode(Int.self, forKey: .ahead)
        behind = try c.decode(Int.self, forKey: .behind)
        repo = try c.decode(String.self, forKey: .repo)
        unpushed = try c.decodeIfPresent(Int.self, forKey: .unpushed)
        baseUnpushed = try c.decodeIfPresent(Int.self, forKey: .baseUnpushed)
    }

    /// `base` can take `branch` without a merge commit.
    public var canFastForward: Bool { ahead > 0 && behind == 0 }
    /// There is something to bring over at all.
    public var hasWork: Bool { ahead > 0 }
    /// `base` holds commits the branch lacks — what "Update from master"
    /// brings in (slice 6), and what blocks a fast-forward the other way.
    public var canUpdate: Bool { behind > 0 }

    /// "worktree-v2 ↑3", "worktree-v2 ↑3 ↓2 ⇡1", "worktree-v2 level". ↑↓
    /// are against master; ⇡ is what is not on origin (starship's glyph
    /// for the same thing).
    public var summary: String {
        var out = branch
        if ahead > 0 { out += " ↑\(ahead)" }
        if behind > 0 { out += " ↓\(behind)" }
        if ahead == 0 && behind == 0 { out += " level" }
        if let unpushed, unpushed > 0 { out += " ⇡\(unpushed)" }
        return out
    }

    /// "⇡2" after the repository when master itself is unpushed.
    public var baseMark: String? {
        guard let baseUnpushed, baseUnpushed > 0 else { return nil }
        return "⇡\(baseUnpushed)"
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
    /// Per repository: master's own unpushed count, keyed like `cache`,
    /// so twenty rows on one repo cost one count.
    private var baseUnpushed: [String: (key: String, count: Int)] = [:]
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
        sha(ofRef: "refs/heads/\(branch)", commonDir: commonDir)
    }

    /// `origin/<branch>` as of the last fetch or push, or nil when origin
    /// has no such branch.
    public static func remoteSHA(of branch: String, commonDir: String) -> String? {
        sha(ofRef: "refs/remotes/origin/\(branch)", commonDir: commonDir)
    }

    /// Any `origin/*` ref at all — without one, "unpushed" means nothing.
    public static func hasOrigin(commonDir: String) -> Bool {
        let dir = URL(filePath: commonDir).appending(path: "refs/remotes/origin")
        if let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path), !names.isEmpty { return true }
        guard let packed = try? String(contentsOf: URL(filePath: commonDir).appending(path: "packed-refs"), encoding: .utf8) else { return false }
        return packed.contains(" refs/remotes/origin/")
    }

    static func sha(ofRef ref: String, commonDir: String) -> String? {
        let loose = URL(filePath: commonDir).appending(path: ref)
        if let text = try? String(contentsOf: loose, encoding: .utf8) {
            let sha = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if sha.count == 40 { return sha }
        }
        guard let packed = try? String(contentsOf: URL(filePath: commonDir).appending(path: "packed-refs"), encoding: .utf8) else { return nil }
        for line in packed.split(separator: "\n") where !line.hasPrefix("#") && !line.hasPrefix("^") {
            let parts = line.split(separator: " ", maxSplits: 1)
            if parts.count == 2, parts[1] == ref { return String(parts[0]) }
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
        // A push moves `origin/<branch>`; that sha is in the key so the
        // unpushed count follows it without a process in between.
        let origin = Self.hasOrigin(commonDir: layout.commonDir)
        let originBranch = origin ? Self.remoteSHA(of: branch, commonDir: layout.commonDir) ?? "-" : "none"
        let originBase = origin ? Self.remoteSHA(of: base, commonDir: layout.commonDir) ?? "-" : "none"
        let key = "\(branchSHA)/\(baseSHA)/\(originBranch)/\(originBase)"
        lock.lock()
        if let entry = cache[cwd], entry.key == key {
            lock.unlock()
            return entry.info
        }
        lock.unlock()
        guard let (ahead, behind) = count(base: base, branch: branch, in: layout.repo) else { return nil }
        var info = WorktreeInfo(branch: branch, base: base, ahead: ahead, behind: behind, repo: layout.repo)
        if origin {
            info.unpushed = unpushedCount(of: branch, in: layout.repo)
            let baseKey = "\(baseSHA)/\(originBase)"
            lock.lock()
            let known = baseUnpushed[layout.repo]
            lock.unlock()
            if let known, known.key == baseKey {
                info.baseUnpushed = known.count
            } else if let n = behindOriginCount(of: base, in: layout.repo) {
                info.baseUnpushed = n
                lock.lock()
                baseUnpushed[layout.repo] = (baseKey, n)
                lock.unlock()
            }
        }
        lock.lock()
        cache[cwd] = Entry(key: key, info: info)
        lock.unlock()
        return info
    }

    /// Master against `origin/master` by name: after a fast-forward to a
    /// pushed branch every commit *is* on origin, under the branch's
    /// name, and the question is still whether the other Mac's master
    /// has them. Nil when origin has no such branch.
    private func behindOriginCount(of branch: String, in repo: String) -> Int? {
        lock.lock(); spawns += 1; lock.unlock()
        guard let out = try? Git.run(git, ["-C", repo, "rev-list", "--count",
                                          "refs/remotes/origin/\(branch)..refs/heads/\(branch)"]).stdout else { return nil }
        return Int(out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `git rev-list --count <branch> --not --remotes=origin`: commits on
    /// the branch that no origin ref reaches. One definition for a branch
    /// with an upstream and one that was never pushed.
    private func unpushedCount(of branch: String, in repo: String) -> Int? {
        lock.lock(); spawns += 1; lock.unlock()
        guard let out = try? Git.run(git, ["-C", repo, "rev-list", "--count", "refs/heads/\(branch)",
                                          "--not", "--remotes=origin"]).stdout else { return nil }
        return Int(out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Always a fresh count — what the merge verb reads before acting.
    public func fresh(forCwd cwd: String) -> WorktreeInfo? {
        lock.lock()
        cache[cwd] = nil
        baseUnpushed = [:]
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
    /// The prompt a session could be asked when the menu could not act
    /// (slice 6): an update that met a conflict backs out and carries
    /// "merge master into this branch and resolve the conflicts" here,
    /// for the HUD's button and `ccc update --ask`. Nil otherwise.
    public var ask: String? = nil
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

/// "Update from master" (v6 slice 6), GitHub's "Update branch" as a
/// verb: `git merge <base>` *inside the worktree* — a merge, never a
/// rewrite, so a session still committing to the branch sees one more
/// commit and nothing moved under it. It acts only at a commit boundary:
/// a worktree with uncommitted changes is refused, since a merge over
/// them could leave the session's half-written edit tangled with
/// master's. A conflict backs out (`merge --abort`) with the files named
/// and carries the one offer a menu cannot make and a session can — ask
/// it to do the merge, as a prompt through the pane.
public enum GitUpdate {
    /// The sentence the session is asked, when it comes to that.
    public static func prompt(base: String) -> String {
        "Merge \(base) into this branch and resolve the conflicts."
    }

    public static func perform(on info: WorktreeInfo, worktree cwd: String,
                               git: String = WorktreeProbe.defaultGit) -> MergeOutcome {
        func g(_ args: [String]) throws -> Git.Result { try Git.run(git, ["-C", cwd] + args) }
        let name = "\(info.base) → \(info.branch)"
        guard info.canUpdate else {
            return MergeOutcome(merged: false, said: "nothing to update: \(info.branch) already has every commit of \(info.base)")
        }
        guard let head = try? g(["symbolic-ref", "--short", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return MergeOutcome(merged: false, said: "the worktree is not on a branch; refusing to update")
        }
        guard head == info.branch else {
            return MergeOutcome(merged: false, said: "the worktree is on \(head), not \(info.branch); refusing to update")
        }
        if let status = try? g(["status", "--porcelain", "--untracked-files=no"]).stdout, !status.isEmpty {
            let n = status.split(separator: "\n").count
            return MergeOutcome(merged: false, said: "\(info.branch) has \(n) uncommitted change\(n == 1 ? "" : "s"); commit or stash first, then update")
        }
        let plural = "\(info.behind) commit\(info.behind == 1 ? "" : "s")"
        do {
            // Plain `merge`: a branch with no commits of its own simply
            // moves up to master (a fast-forward is not a rewrite); one
            // with work gets a merge commit. `-m` names it either way.
            _ = try g(["merge", "--no-edit", "-m", "Merge \(info.base) into \(info.branch) (\(plural))", "refs/heads/\(info.base)"])
            let sha = (try? g(["rev-parse", "--short", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
            if info.ahead == 0 {
                return MergeOutcome(merged: true, said: "fast-forwarded \(info.branch) to \(info.base) (\(plural), now \(sha))")
            }
            return MergeOutcome(merged: true, said: "merged \(name) (\(plural), merge commit \(sha))")
        } catch {
            let conflicts = conflictedFiles(g)
            _ = try? g(["merge", "--abort"])
            return MergeOutcome(merged: false,
                                said: "merge \(name) conflicts in \(conflicts); backed out, \(info.branch) untouched — ask the session to merge \(info.base)",
                                ask: prompt(base: info.base))
        }
    }

    private static func conflictedFiles(_ g: ([String]) throws -> Git.Result) -> String {
        let files = (try? g(["diff", "--name-only", "--diff-filter=U"]).stdout)?
            .split(separator: "\n").map(String.init) ?? []
        if files.isEmpty { return "the working tree" }
        return files.prefix(4).joined(separator: ", ") + (files.count > 4 ? " (+\(files.count - 4))" : "")
    }
}

/// Which branch `ccc push <ref>` sends: the worktree's own, or the
/// repository's default branch after a fast-forward landed on it.
public enum PushTarget: String, CaseIterable, Codable, Sendable {
    case branch, base

    public var flag: String? { self == .base ? "--base" : nil }
}

/// The push itself: `git push origin <name>`, never forced, from the
/// main checkout. What it refuses it refuses by git's own rule — a
/// remote that moved is a non-fast-forward and git says so — and a
/// refusal is the sentence, exit 1, nothing changed anywhere. The other
/// direction (fetch, pull) is not here: the roster reads what the last
/// fetch left and never asks the network on its own.
public enum GitPush {
    public static func perform(_ target: PushTarget, on info: WorktreeInfo,
                               git: String = WorktreeProbe.defaultGit) -> MergeOutcome {
        let name = target == .base ? info.base : info.branch
        let count = target == .base ? info.baseUnpushed : info.unpushed
        guard let count else {
            return MergeOutcome(merged: false, said: "\(info.repo) has no origin; nothing to push to")
        }
        guard count > 0 else {
            return MergeOutcome(merged: false, said: "nothing to push: origin/\(name) already has every commit of \(name)")
        }
        let plural = "\(count) commit\(count == 1 ? "" : "s")"
        do {
            // `-u` once for a branch origin never had, so a later plain
            // `git push` in a shell knows where to go. Never `--force`.
            _ = try Git.run(git, ["-C", info.repo, "push", "--porcelain", "-u", "origin", "refs/heads/\(name):refs/heads/\(name)"])
            return MergeOutcome(merged: true, said: "pushed \(name) → origin (\(plural))")
        } catch {
            let detail = "\(error)".trimmingCharacters(in: .whitespacesAndNewlines)
            let why = detail.contains("non-fast-forward") || detail.contains("fetch first") || detail.contains("rejected")
                ? "origin/\(name) has moved; fetch and merge in a terminal, then push again"
                : detail
            return MergeOutcome(merged: false, said: "push \(name) refused: \(why)")
        }
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

    /// `ccc push <id> [--base]` on a remote host: the far side's own ccc,
    /// where the repository and its credentials are.
    public func pushArgv(_ target: PushTarget, id: String) -> [String]? {
        guard let ccc = host.ccc, let destination = host.ssh else { return nil }
        return sshPrefix(tty: false, destination: destination) + [ccc, "push", id] + (target.flag.map { [$0] } ?? [])
    }

    /// Push a session's worktree branch, or its repository's default
    /// branch, to origin. Same road as `merge`: the row's cwd from one
    /// roster read, a fresh count, `GitPush` off the main actor; the far
    /// side's verb for a remote ref.
    public func push(_ target: PushTarget, id: String, probe: WorktreeProbe = WorktreeProbe()) async throws -> MergeOutcome {
        if host.isLocal {
            let roster = RosterDecoder.decode(try await agentsJSON())
            guard let row = roster.sessions.first(where: { $0.id == id }) else {
                throw MergeError.noSuchSession(id)
            }
            guard let info = probe.fresh(forCwd: row.cwd) else {
                throw MergeError.notAWorktree(id, row.cwd)
            }
            return await Task.detached(priority: .userInitiated) { GitPush.perform(target, on: info, git: probe.git) }.value
        }
        guard let argv = pushArgv(target, id: id) else { throw MergeError.noRemoteCCC(host.name) }
        try prepareControlDirectory()
        let result = try await run(argv, accepting: [0, 1], program: "ccc")
        let said = (String(decoding: result.stdout, as: UTF8.self) + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        return MergeOutcome(merged: result.status == 0, said: said)
    }

    /// `ccc update <id> --json` on a remote host: the far side's own ccc,
    /// where the worktree is. `--json`, because the answer has a shape —
    /// the offered prompt on a conflict — that a sentence cannot carry.
    public func updateArgv(id: String) -> [String]? {
        guard let ccc = host.ccc, let destination = host.ssh else { return nil }
        return sshPrefix(tty: false, destination: destination) + [ccc, "update", id, "--json"]
    }

    /// Update a session's worktree branch from the repository's default
    /// branch (slice 6). Same road as `merge`: the row's cwd from one
    /// roster read, a fresh count, `GitUpdate` off the main actor in the
    /// worktree; the far side's verb for a remote ref, its JSON read
    /// leniently (a sentence alone, off a ccc that printed one, is the
    /// sentence).
    public func update(id: String, probe: WorktreeProbe = WorktreeProbe()) async throws -> MergeOutcome {
        if host.isLocal {
            let roster = RosterDecoder.decode(try await agentsJSON())
            guard let row = roster.sessions.first(where: { $0.id == id }) else {
                throw MergeError.noSuchSession(id)
            }
            guard let info = probe.fresh(forCwd: row.cwd) else {
                throw MergeError.notAWorktree(id, row.cwd)
            }
            let cwd = row.cwd
            return await Task.detached(priority: .userInitiated) { GitUpdate.perform(on: info, worktree: cwd, git: probe.git) }.value
        }
        guard let argv = updateArgv(id: id) else { throw MergeError.noRemoteCCC(host.name) }
        try prepareControlDirectory()
        let result = try await run(argv, accepting: [0, 1], program: "ccc")
        let text = String(decoding: result.stdout, as: UTF8.self)
        if let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
           let said = object["said"] as? String {
            return MergeOutcome(merged: result.status == 0, said: said, ask: object["ask"] as? String)
        }
        let said = (text + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
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
