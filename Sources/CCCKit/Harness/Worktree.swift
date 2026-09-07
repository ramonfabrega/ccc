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
    /// Whether `base` was recorded for this branch (`branch.<b>.ccc-base`,
    /// written by `ccc spawn --base` and `ccc base`, or VS Code's
    /// `vscode-merge-base`) rather than being the repository's default
    /// branch. Nil off an older ccc, where it was always the default.
    public var baseRecorded: Bool?
    /// **Which tip of the base `ahead`/`behind` are counted against, and
    /// `update` merges** (2026-09-06). `nil` is the ordinary answer, the
    /// local `refs/heads/<base>`; `origin/<base>` when origin strictly
    /// holds every commit the local base has and more.
    ///
    /// It exists because of a shape the fleet makes constantly and a lone
    /// repository never does: **the base branch is checked out in another
    /// session's worktree.** attrition's commander holds
    /// `worktree-replan-pdb` while every worker branches off it, so
    /// `ccc pull` — which fast-forwards in the main checkout and refuses
    /// unless `HEAD == base` — has no way to advance the local ref, and a
    /// worker that used it would be writing into a live agent's tree.
    /// Following origin's tip instead makes `ccc update <ref>` do exactly
    /// what a worker's `git merge origin/<base>` did, with the column
    /// counting the same commits the verb would bring. A base that has
    /// *diverged* from origin stays local: that is a human's problem, not
    /// a side for ccc to pick. Nil off an older ccc across the hop.
    public var baseTip: String?
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
    /// The mirror of `unpushed` (slice 7): commits on `origin/<branch>`
    /// that the branch lacks — another Mac pushed to it. As of the last
    /// fetch, never a network call. Nil when origin has no such branch.
    /// Informative only: pulling into the worktree branch is rebase's
    /// problem by another name and stays a terminal's.
    public var unpulled: Int?
    /// `origin/<base>` ahead of `base`: what Pull master brings, and what
    /// makes Push master a non-fast-forward. Nil when origin has no such
    /// branch.
    public var baseUnpulled: Int?

    public init(branch: String, base: String, ahead: Int, behind: Int, repo: String,
                unpushed: Int? = nil, baseUnpushed: Int? = nil,
                unpulled: Int? = nil, baseUnpulled: Int? = nil) {
        self.branch = branch
        self.base = base
        self.ahead = ahead
        self.behind = behind
        self.repo = repo
        self.unpushed = unpushed
        self.baseUnpushed = baseUnpushed
        self.unpulled = unpulled
        self.baseUnpulled = baseUnpulled
    }

    /// Lenient on what slice 2 added: a slice-1 ccc on the far side sends
    /// no `unpushed`, and that must not cost the row its branch.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        branch = try c.decode(String.self, forKey: .branch)
        base = try c.decode(String.self, forKey: .base)
        baseRecorded = try c.decodeIfPresent(Bool.self, forKey: .baseRecorded)
        baseTip = try c.decodeIfPresent(String.self, forKey: .baseTip)
        ahead = try c.decode(Int.self, forKey: .ahead)
        behind = try c.decode(Int.self, forKey: .behind)
        repo = try c.decode(String.self, forKey: .repo)
        unpushed = try c.decodeIfPresent(Int.self, forKey: .unpushed)
        baseUnpushed = try c.decodeIfPresent(Int.self, forKey: .baseUnpushed)
        unpulled = try c.decodeIfPresent(Int.self, forKey: .unpulled)
        baseUnpulled = try c.decodeIfPresent(Int.self, forKey: .baseUnpulled)
    }

    /// The ref `update` merges and `behind` is counted against.
    public var baseTipRef: String { baseTip.map { "refs/remotes/\($0)" } ?? "refs/heads/\(base)" }
    /// What to call that tip in a sentence: `master`, or `origin/master`.
    public var baseTipName: String { baseTip ?? base }

    /// `base` can take `branch` without a merge commit.
    public var canFastForward: Bool { ahead > 0 && behind == 0 }
    /// There is something to bring over at all.
    public var hasWork: Bool { ahead > 0 }
    /// `base` holds commits the branch lacks — what "Update from master"
    /// brings in (slice 6), and what blocks a fast-forward the other way.
    public var canUpdate: Bool { behind > 0 }
    /// `origin/<base>` holds commits `base` lacks, as of the last fetch —
    /// what Pull master brings (slice 7).
    public var canPull: Bool { (baseUnpulled ?? 0) > 0 }

    /// "worktree-v2 ↑3", "worktree-v2 ↑3 ↓2 ⇡1 ⇣1", "worktree-v2 level".
    /// ↑↓ are against master; ⇡ is what is not on origin, ⇣ what origin
    /// has that this does not (starship's glyphs for the same things).
    public var summary: String {
        var out = branch
        if ahead > 0 { out += " ↑\(ahead)" }
        if behind > 0 { out += " ↓\(behind)" }
        if ahead == 0 && behind == 0 { out += " level" }
        if let unpushed, unpushed > 0 { out += " ⇡\(unpushed)" }
        if let unpulled, unpulled > 0 { out += " ⇣\(unpulled)" }
        return out
    }

    /// Against origin, in words: "worktree-t 1 unpushed, 2 unpulled;
    /// master has 1 unpulled", or "level with origin". What a fetch
    /// answers with.
    public var originStanding: String {
        var mine: [String] = []
        if let unpushed, unpushed > 0 { mine.append("\(unpushed) unpushed") }
        if let unpulled, unpulled > 0 { mine.append("\(unpulled) unpulled") }
        var theirs: [String] = []
        if let baseUnpushed, baseUnpushed > 0 { theirs.append("\(baseUnpushed) unpushed") }
        if let baseUnpulled, baseUnpulled > 0 { theirs.append("\(baseUnpulled) unpulled") }
        var parts: [String] = []
        if !mine.isEmpty { parts.append("\(branch) " + mine.joined(separator: ", ")) }
        if !theirs.isEmpty { parts.append("\(base) has " + theirs.joined(separator: ", ")) }
        return parts.isEmpty ? "level with origin" : parts.joined(separator: "; ")
    }

    /// "⇡2", "⇣1", "⇡2 ⇣1" after the repository when master itself is
    /// unpushed or behind origin.
    public var baseMark: String? {
        var parts: [String] = []
        if let baseUnpushed, baseUnpushed > 0 { parts.append("⇡\(baseUnpushed)") }
        if let baseUnpulled, baseUnpulled > 0 { parts.append("⇣\(baseUnpulled)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
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
    /// Per repository: the bases recorded in `.git/config`, re-read when
    /// the file's mtime moves (one `stat` per row per tick otherwise).
    private var recorded: [String: (modified: Date?, bases: [String: String])] = [:]
    /// Per repository: master's own standing against origin (unpulled,
    /// unpushed), keyed like `cache`, so twenty rows on one repo cost one
    /// count.
    private var baseStanding: [String: (key: String, unpulled: Int, unpushed: Int)] = [:]
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

    // MARK: the recorded base (item 18)

    /// The base recorded for `branch` in the repository's config, if any.
    /// Caller holds `lock`. Re-parsed when the file's mtime moves.
    private func recordedBase(for branch: String, commonDir: String, repo: String) -> String? {
        let path = commonDir + "/config"
        let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        if let known = recorded[repo], known.modified == modified { return known.bases[branch] }
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let bases = Self.recordedBases(in: text)
        recorded[repo] = (modified, bases)
        return bases[branch]
    }

    /// `[branch "<name>"]` sections of a git config, read for two keys:
    /// ours, `ccc-base = <branch>`, and VS Code's `vscode-merge-base =
    /// origin/<branch>` (honoured because it means the same thing and is
    /// already in the fleet's configs; ours wins where both exist).
    /// Lenient: anything that is not one of those two lines is skipped.
    public static func recordedBases(in config: String) -> [String: String] {
        var ours: [String: String] = [:]
        var theirs: [String: String] = [:]
        var section: String?
        for raw in config.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                section = nil
                let prefix = "[branch \""
                if line.hasPrefix(prefix), let end = line.range(of: "\"]") {
                    section = String(line[line.index(line.startIndex, offsetBy: prefix.count)..<end.lowerBound])
                }
                continue
            }
            guard let section, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[1].isEmpty else { continue }
            switch parts[0].lowercased() {
            case "ccc-base":
                ours[section] = parts[1]
            case "vscode-merge-base":
                theirs[section] = parts[1].hasPrefix("origin/") ? String(parts[1].dropFirst("origin/".count)) : parts[1]
            default:
                break
            }
        }
        return theirs.merging(ours) { _, mine in mine }
    }

    /// Record — or with `nil`, forget — the base for a branch:
    /// `git config branch.<branch>.ccc-base <base>` in the repository.
    /// The one write in this file, and it is to a key of ours in git's
    /// own config, never to a ref. The next tick reads it (mtime).
    public static func recordBase(_ base: String?, for branch: String, repo: String, git: String = defaultGit) throws {
        if let base {
            _ = try Git.run(git, ["-C", repo, "config", "branch.\(branch).ccc-base", base])
        } else {
            do {
                _ = try Git.run(git, ["-C", repo, "config", "--unset", "branch.\(branch).ccc-base"])
            } catch let failure as Git.Failure where failure.status == 5 {
                // git's "no such key": nothing to forget.
            }
        }
    }

    /// The git checkout a folder is in — a linked worktree, or the main
    /// checkout itself (whose `.git` is a directory) — with the branch it
    /// is on. Nil outside any repository. What `ccc spawn` asks before
    /// cutting a worktree: which repo, and which branch the asker is on.
    public struct Checkout: Equatable, Sendable {
        public var repo: String
        public var commonDir: String
        public var branch: String?
    }

    public static func checkout(of cwd: String) -> Checkout? {
        if let layout = layout(of: cwd) {
            return Checkout(repo: layout.repo, commonDir: layout.commonDir, branch: layout.branch)
        }
        var dir = URL(filePath: cwd).standardizedFileURL
        while true {
            let dotGit = dir.appending(path: ".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory), isDirectory.boolValue {
                let head = (try? String(contentsOf: dotGit.appending(path: "HEAD"), encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let branch = head.hasPrefix("ref: refs/heads/") ? String(head.dropFirst("ref: refs/heads/".count)) : nil
                return Checkout(repo: dir.path, commonDir: dotGit.path, branch: branch)
            }
            let parent = dir.deletingLastPathComponent()
            guard parent.path != dir.path, dir.path != "/" else { return nil }
            dir = parent
        }
    }

    /// A worktree name from a session name: lowercase, `-` for anything a
    /// path or a branch would mind, nil when nothing is left.
    public static func worktreeName(from name: String) -> String? {
        var out = ""
        for scalar in name.lowercased().unicodeScalars {
            switch scalar {
            case "a"..."z", "0"..."9", "-", "_", ".": out.unicodeScalars.append(scalar)
            default: if !out.hasSuffix("-") { out.append("-") }
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return trimmed.isEmpty ? nil : String(trimmed.prefix(40))
    }

    /// Cut a worktree the way the harness lays them out —
    /// `<repo>/.claude/worktrees/<name>` on `worktree-<name>` — off `base`,
    /// and record the base for it (item 18). Refuses a base that does not
    /// resolve and a name a shell or git would mind; git's own refusals
    /// (a branch that exists, a path that does) pass through as the
    /// sentence, nothing made.
    public static func createWorktree(named name: String, base: String, repo: String,
                                      git: String = defaultGit) throws -> SpawnResult.MadeWorktree {
        guard worktreeName(from: name) == name else {
            throw SpawnError(description: "'\(name)' is not a worktree name (letters, digits, - _ .)")
        }
        let commonDir = repo + "/.git"
        guard sha(of: base, commonDir: commonDir) != nil else {
            throw SpawnError(description: "no local branch '\(base)' in \(repo) to cut a worktree from")
        }
        let branch = "worktree-\(name)"
        let path = repo + "/.claude/worktrees/\(name)"
        guard !FileManager.default.fileExists(atPath: path) else {
            throw SpawnError(description: "\(path) already exists; --worktree=<name> picks another")
        }
        try FileManager.default.createDirectory(atPath: repo + "/.claude/worktrees", withIntermediateDirectories: true)
        do {
            _ = try Git.run(git, ["-C", repo, "worktree", "add", "-q", "-b", branch, path, base])
        } catch {
            throw SpawnError(description: "git worktree add \(branch) off \(base): \(error)")
        }
        try recordBase(base, for: branch, repo: repo, git: git)
        return SpawnResult.MadeWorktree(path: path, branch: branch, base: base)
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
        let baseRecorded: Bool
        lock.lock()
        // The base, in order (queue item 18): the one recorded for this
        // branch in the repo's config, else the default branch. Either is
        // trusted only while it still resolves: after `git branch -m
        // master main` the old name has no ref, and a probe that lives as
        // long as the app (the poller's) would otherwise blank the column
        // for every worktree of that repo until relaunch (found
        // 2026-09-04). One ref read per row per tick buys the check.
        if let pinned = recordedBase(for: branch, commonDir: layout.commonDir, repo: layout.repo),
           Self.sha(of: pinned, commonDir: layout.commonDir) != nil {
            base = pinned
            baseRecorded = true
        } else if let known = bases[layout.repo], Self.sha(of: known, commonDir: layout.commonDir) != nil {
            base = known
            baseRecorded = false
        } else {
            guard let found = Self.defaultBranch(commonDir: layout.commonDir) else {
                bases[layout.repo] = nil
                lock.unlock()
                return nil
            }
            bases[layout.repo] = found
            base = found
            baseRecorded = false
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
        // The base's *name* is in the key: a rename leaves every sha where
        // it was, and a key of shas alone handed back the entry that still
        // said `master`.
        let key = "\(branchSHA)/\(base)@\(baseSHA)/\(originBranch)/\(originBase)"
        lock.lock()
        if let entry = cache[cwd], entry.key == key {
            lock.unlock()
            return entry.info
        }
        lock.unlock()
        // The base's standing against origin is read *first*, because it
        // decides which tip the counts below are against (2026-09-06).
        var baseUnpushed: Int?
        var baseUnpulled: Int?
        var unpushed: Int?
        var unpulled: Int?
        if origin {
            unpushed = unpushedCount(of: branch, in: layout.repo)
            // ⇣ on the branch only once origin has it (slice 7): before the
            // first push there is nothing to be behind.
            if originBranch != "-" {
                unpulled = originStanding(of: branch, in: layout.repo)?.unpulled
            }
            let baseKey = "\(baseSHA)/\(originBase)"
            lock.lock()
            let known = baseStanding[layout.repo]
            lock.unlock()
            if let known, known.key == baseKey {
                baseUnpushed = known.unpushed
                baseUnpulled = known.unpulled
            } else if let standing = originStanding(of: base, in: layout.repo) {
                baseUnpushed = standing.unpushed
                baseUnpulled = standing.unpulled
                lock.lock()
                baseStanding[layout.repo] = (baseKey, standing.unpulled, standing.unpushed)
                lock.unlock()
            }
        }
        // **Which tip is the base?** Normally `refs/heads/<base>`. But a
        // fleet's base branch is usually checked out in *another* session's
        // worktree — attrition's commander holds `worktree-replan-pdb` while
        // its workers branch off it — and `ccc pull` cannot advance a ref
        // it does not have checked out. So when origin strictly holds every
        // local commit and more, origin's is the tip: the worker's
        // `git merge origin/<base>` and ccc's `↓N` then mean the same thing,
        // and nobody's worktree is written to on someone else's behalf.
        // A *diverged* base stays local — that is a mess for a human, not a
        // thing to pick a side in. Costs no process: the standing above is
        // exactly the comparison.
        let tip: String? = (baseUnpushed == 0 && (baseUnpulled ?? 0) > 0) ? "origin/\(base)" : nil
        let tipRef = tip.map { "refs/remotes/\($0)" } ?? "refs/heads/\(base)"
        guard let (ahead, behind) = count(baseRef: tipRef, branch: branch, in: layout.repo) else { return nil }
        var info = WorktreeInfo(branch: branch, base: base, ahead: ahead, behind: behind, repo: layout.repo)
        info.baseRecorded = baseRecorded
        info.baseTip = tip
        info.unpushed = unpushed
        info.unpulled = unpulled
        info.baseUnpushed = baseUnpushed
        info.baseUnpulled = baseUnpulled
        lock.lock()
        cache[cwd] = Entry(key: key, info: info)
        lock.unlock()
        return info
    }

    /// A branch against `origin/<branch>` by name, both ways in one
    /// process: `rev-list --left-right --count origin/b...b` → (unpulled,
    /// unpushed). For master, "unpushed by name" is the reading that
    /// survives a fast-forward to a pushed branch — every commit *is* on
    /// origin, under the branch's name, and the question is still whether
    /// the other Mac's master has them. Nil when origin has no such branch.
    private func originStanding(of branch: String, in repo: String) -> (unpulled: Int, unpushed: Int)? {
        lock.lock(); spawns += 1; lock.unlock()
        guard let out = try? Git.run(git, ["-C", repo, "rev-list", "--left-right", "--count",
                                          "refs/remotes/origin/\(branch)...refs/heads/\(branch)"]).stdout else { return nil }
        let parts = out.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, let unpulled = Int(parts[0]), let unpushed = Int(parts[1]) else { return nil }
        return (unpulled, unpushed)
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
        baseStanding = [:]
        lock.unlock()
        return info(forCwd: cwd)
    }

    /// `git rev-list --left-right --count <baseRef>...branch` → (ahead,
    /// behind). `baseRef` is a full ref because it is not always the local
    /// base branch (see `WorktreeInfo.baseTip`).
    private func count(baseRef: String, branch: String, in repo: String) -> (Int, Int)? {
        lock.lock(); spawns += 1; lock.unlock()
        guard let out = try? Git.run(git, ["-C", repo, "rev-list", "--left-right", "--count",
                                          "\(baseRef)...refs/heads/\(branch)"]).stdout else { return nil }
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
                return MergeOutcome(merged: false, said: "\(info.baseTipName) has moved \(info.behind) commit\(info.behind == 1 ? "" : "s") past \(info.branch); a fast-forward is not possible — `ccc update` first, then merge or squash")
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
        // The tip, not the base branch by name: `origin/<base>` when the
        // local ref is behind it, which on this fleet is the ordinary case
        // for a base another session's worktree holds checked out.
        let tip = info.baseTipName
        let name = "\(tip) → \(info.branch)"
        guard info.canUpdate else {
            return MergeOutcome(merged: false, said: "nothing to update: \(info.branch) already has every commit of \(tip)")
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
            _ = try g(["merge", "--no-edit", "-m", "Merge \(tip) into \(info.branch) (\(plural))", info.baseTipRef])
            let sha = (try? g(["rev-parse", "--short", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
            if info.ahead == 0 {
                return MergeOutcome(merged: true, said: "fast-forwarded \(info.branch) to \(tip) (\(plural), now \(sha))")
            }
            return MergeOutcome(merged: true, said: "merged \(name) (\(plural), merge commit \(sha))")
        } catch {
            let conflicts = conflictedFiles(g)
            _ = try? g(["merge", "--abort"])
            return MergeOutcome(merged: false,
                                said: "merge \(name) conflicts in \(conflicts); backed out, \(info.branch) untouched — ask the session to merge \(tip)",
                                ask: prompt(base: tip))
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

/// Fetch (v6 slice 7): the one network call the roster ever makes, and
/// only when asked — the submenu's Fetch, `ccc fetch <ref>`, once on
/// launch and once on wake. Everything the rows read stays "as of the
/// last fetch"; this is what moves that instant. `git fetch origin` in
/// the main checkout: refs only, nothing merged, nothing pruned.
public enum GitFetch {
    public static func perform(repo: String, git: String = WorktreeProbe.defaultGit) -> MergeOutcome {
        let started = ContinuousClock.now
        do {
            _ = try Git.run(git, ["-C", repo, "fetch", "--quiet", "origin"])
            let ms = (ContinuousClock.now - started).ms
            return MergeOutcome(merged: true, said: "fetched origin (\(ms) ms)")
        } catch {
            return MergeOutcome(merged: false, said: "fetch origin failed: \("\(error)".trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}

/// Pull master (v6 slice 7): the mirror of Push master, fast-forward
/// only. `git merge --ff-only origin/<base>` in the main checkout, with
/// the merge verb's guards (on the base branch, clean). A master that
/// diverged from origin is refused with the way out named — push first,
/// or merge in a terminal — never a merge commit on master by a menu.
/// Into the worktree branch is not offered: that is rebase's problem by
/// another name.
public enum GitPull {
    public static func perform(on info: WorktreeInfo, git: String = WorktreeProbe.defaultGit) -> MergeOutcome {
        let repo = info.repo, base = info.base
        func g(_ args: [String]) throws -> Git.Result { try Git.run(git, ["-C", repo] + args) }
        guard let count = info.baseUnpulled else {
            return MergeOutcome(merged: false, said: "\(repo) has no origin/\(base) to pull from")
        }
        guard count > 0 else {
            return MergeOutcome(merged: false, said: "nothing to pull: \(base) already has every commit of origin/\(base), as of the last fetch")
        }
        guard let head = try? g(["symbolic-ref", "--short", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return MergeOutcome(merged: false, said: "\(repo) is not on a branch; refusing to pull")
        }
        guard head == base else {
            return MergeOutcome(merged: false, said: "\(repo) is on \(head), not \(base); refusing to pull")
        }
        if let status = try? g(["status", "--porcelain", "--untracked-files=no"]).stdout, !status.isEmpty {
            let n = status.split(separator: "\n").count
            return MergeOutcome(merged: false, said: "\(repo) has \(n) uncommitted change\(n == 1 ? "" : "s"); refusing to pull")
        }
        let plural = "\(count) commit\(count == 1 ? "" : "s")"
        if let unpushed = info.baseUnpushed, unpushed > 0 {
            return MergeOutcome(merged: false, said: "\(base) has \(unpushed) commit\(unpushed == 1 ? "" : "s") origin/\(base) lacks; a fast-forward is not possible — push \(base) first, or merge in a terminal")
        }
        do {
            _ = try g(["merge", "--ff-only", "refs/remotes/origin/\(base)"])
            let sha = (try? g(["rev-parse", "--short", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
            return MergeOutcome(merged: true, said: "pulled origin/\(base) → \(base) (\(plural), now \(sha))")
        } catch {
            return MergeOutcome(merged: false, said: "pull \(base) refused: \("\(error)".trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}

extension Duration {
    /// Whole milliseconds, for a sentence.
    public var ms: Int { Int(self / .milliseconds(1)) }
}

/// `git` as a subprocess: stdout and stderr to EOF, a non-zero exit as an
/// error carrying stderr. Synchronous; every caller is already off the
/// main actor or is the CLI.
public enum Git {
    public struct Result: Sendable {
        public var stdout: String
        public var stderr: String
    }

    /// One pipe read to EOF on a background thread, for the synchronous
    /// runners (`Git.run`, `Tailnet.scan`) that block on the other pipe.
    /// `data` waits for EOF. The async runners use `Subprocess` instead.
    public final class Drain: @unchecked Sendable {
        private var collected = Data()
        private let done = DispatchSemaphore(value: 0)

        public init(_ handle: FileHandle) {
            DispatchQueue.global(qos: .utility).async {
                self.collected = handle.readDataToEndOfFile()
                self.done.signal()
            }
        }

        public var data: Data {
            done.wait()
            done.signal()   // stays consumed-once for any later reader too
            return collected
        }
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
        // stderr drains on its own thread while this one reads stdout to
        // EOF: read one after the other and a child that fills the 64 KiB
        // stderr pipe before closing stdout blocks in write(2) forever,
        // and so does this (measured 2026-09-04: fine at 65,536 bytes,
        // a permanent hang at 66,000). No git command run here says that
        // much on stderr today; the shape was wrong regardless.
        let stderr = Drain(err.fileHandleForReading)
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let result = Result(stdout: String(decoding: stdout, as: UTF8.self), stderr: String(decoding: stderr.data, as: UTF8.self))
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

    /// What `ccc base <ref>` answers: the branch, what it is measured
    /// against, and whether that was recorded or is the default.
    public struct BaseReading: Codable, Sendable, Equatable {
        public var branch: String
        public var base: String
        public var recorded: Bool
        public var said: String
    }

    /// `ccc base <id> [<branch> | --clear]` on a remote host: the far
    /// side's own ccc, where the repository is.
    public func baseArgv(id: String, set: String?, clear: Bool) -> [String]? {
        guard let ccc = host.ccc, let destination = host.ssh else { return nil }
        var words = [ccc, "base", id, "--json"]
        if let set { words.append(set) }
        if clear { words.append("--clear") }
        return sshPrefix(tty: false, destination: destination) + words
    }

    /// Read, record or forget the base of a session's worktree branch
    /// (item 18). The read half of what `ccc list --json` shows as
    /// `worktree.base`, and the write half that the twin rule owes it —
    /// a worktree cut by hand off `storefront` can say so here, and the
    /// column, `merge`, `update` and `pull` follow on the next tick.
    /// Same road as `merge`: the row's cwd from one roster read, then git,
    /// or the far side's verb for a remote ref.
    public func base(id: String, set: String? = nil, clear: Bool = false,
                     probe: WorktreeProbe = WorktreeProbe()) async throws -> BaseReading {
        if host.isLocal {
            let roster = RosterDecoder.decode(try await agentsJSON())
            guard let row = roster.sessions.first(where: { $0.id == id }) else {
                throw MergeError.noSuchSession(id)
            }
            guard let layout = WorktreeProbe.layout(of: row.cwd), let branch = layout.branch else {
                throw MergeError.notAWorktree(id, row.cwd)
            }
            if let set {
                guard WorktreeProbe.sha(of: set, commonDir: layout.commonDir) != nil else {
                    throw SpawnError(description: "no local branch '\(set)' in \(layout.repo)")
                }
                try WorktreeProbe.recordBase(set, for: branch, repo: layout.repo, git: probe.git)
            } else if clear {
                try WorktreeProbe.recordBase(nil, for: branch, repo: layout.repo, git: probe.git)
            }
            guard let info = probe.fresh(forCwd: row.cwd) else {
                throw MergeError.notAWorktree(id, row.cwd)
            }
            let recorded = info.baseRecorded ?? false
            let verb = set != nil ? "recorded" : clear ? "cleared to" : recorded ? "recorded" : "default"
            return BaseReading(branch: info.branch, base: info.base, recorded: recorded,
                               said: "\(info.branch) is measured against \(info.base) (\(verb)); \(info.summary)")
        }
        guard let argv = baseArgv(id: id, set: set, clear: clear) else { throw MergeError.noRemoteCCC(host.name) }
        try prepareControlDirectory()
        let out = try await run(argv, program: "ccc")
        do {
            return try JSONDecoder().decode(BaseReading.self, from: out)
        } catch {
            throw SpawnError(description: "`ccc base` on \(host.name) answered something that is not a reading (an older ccc there?)")
        }
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

    /// The row and its worktree reading for a local ref: one roster read,
    /// a fresh count. What every worktree verb starts from.
    func localWorktree(id: String, probe: WorktreeProbe) async throws -> (cwd: String, info: WorktreeInfo) {
        let roster = RosterDecoder.decode(try await agentsJSON())
        guard let row = roster.sessions.first(where: { $0.id == id }) else {
            throw MergeError.noSuchSession(id)
        }
        guard let info = probe.fresh(forCwd: row.cwd) else {
            throw MergeError.notAWorktree(id, row.cwd)
        }
        return (row.cwd, info)
    }

    /// `ccc fetch|pull <id>` on a remote host: the far side's own ccc,
    /// where the repository and its credentials are.
    public func remoteVerbArgv(_ verb: String, id: String) -> [String]? {
        guard let ccc = host.ccc, let destination = host.ssh else { return nil }
        return sshPrefix(tty: false, destination: destination) + [ccc, verb, id]
    }

    private func remoteVerb(_ verb: String, id: String) async throws -> MergeOutcome {
        guard let argv = remoteVerbArgv(verb, id: id) else { throw MergeError.noRemoteCCC(host.name) }
        try prepareControlDirectory()
        let result = try await run(argv, accepting: [0, 1], program: "ccc")
        let said = (String(decoding: result.stdout, as: UTF8.self) + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        return MergeOutcome(merged: result.status == 0, said: said)
    }

    /// Fetch the session's repository from origin (slice 7), then say
    /// where things stand now: "fetched origin (312 ms); master has 2
    /// unpulled". The far side's own verb for a remote ref.
    public func fetch(id: String, probe: WorktreeProbe = WorktreeProbe()) async throws -> MergeOutcome {
        guard host.isLocal else { return try await remoteVerb("fetch", id: id) }
        let (cwd, info) = try await localWorktree(id: id, probe: probe)
        guard info.unpushed != nil else {
            return MergeOutcome(merged: false, said: "\(info.repo) has no origin; nothing to fetch from")
        }
        let repo = info.repo
        var outcome = await Task.detached(priority: .userInitiated) { GitFetch.perform(repo: repo, git: probe.git) }.value
        if outcome.merged, let after = probe.fresh(forCwd: cwd) {
            outcome.said += "; " + after.originStanding
        }
        return outcome
    }

    /// Pull the repository's default branch, fast-forward only (slice 7).
    public func pull(id: String, probe: WorktreeProbe = WorktreeProbe()) async throws -> MergeOutcome {
        guard host.isLocal else { return try await remoteVerb("pull", id: id) }
        let (_, info) = try await localWorktree(id: id, probe: probe)
        return await Task.detached(priority: .userInitiated) { GitPull.perform(on: info, git: probe.git) }.value
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
