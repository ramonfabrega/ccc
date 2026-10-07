import Foundation

/// `ccc forget <ref>`: drop a finished row from the roster and keep
/// everything it stood on — the worktree, the branch, whatever is in them.
///
/// **It is `claude rm` with the one case that takes a tree refused**, not a
/// second deleter. The daemon is the only thing that can drop a row and
/// ccc never writes its files (CLAUDE.md), so the verb is the harness's
/// own `rm`, run only when the rule says it will take nothing else.
///
/// The rule, measured 2026-10-07 on owned fixtures
/// (`docs/EVIDENCE.md` "forget — what `claude rm` takes"): `claude rm`
/// removes a worktree **only when the job file names one** —
/// `worktreePath` in `~/.claude/jobs/<id>/state.json`, which the harness
/// writes for a tree it cut itself (`--worktree`). Two sessions launched
/// with `--cwd` into one clean, pushed worktree were each answered
/// `removed <id>`, no `worktree:` line, and the tree and its branch
/// outlived both; a third, spawned with `--worktree`, carried
/// `worktreePath` and its `rm` took the tree. `ccc rm` adds the trees ccc
/// cut (`ccc-cut`), so those are refused too.
///
/// Asked for by attrition's loop, whose `spawn --replace` hand-offs left a
/// stopped row per hand-off on a worktree several sessions share and that
/// holds a 21 GB target: `ccc rm` was safe there and nothing said so, and
/// a verb whose safety has to be remembered is a verb nobody reaches for.
public enum ForgetGuard {
    /// The tree `claude rm` would take with this job: the path its job file
    /// names, or nil. Lenient like every read of that file — no file, no
    /// key, or a value of the wrong type is "names none".
    public static func harnessWorktree(forJob id: String,
                                       jobsDirectory: URL = DraftProbe.defaultJobsDirectory) -> String? {
        let url = jobsDirectory.appending(path: id).appending(path: "state.json")
        guard let data = try? Data(contentsOf: url),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let path = object["worktreePath"] as? String else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Why this row may not be forgotten, or nil when `claude rm` would
    /// take the row and nothing else.
    ///
    /// **Finished means no process, not a state.** `done` is the end of a
    /// *turn*: the live `steer` this verb was built for read `state: done,
    /// status: busy` while it was answering. On the roster `status` and
    /// `pid` arrive together and only while something is attached (19 rows,
    /// 2026-10-07), so either one present is a session that is still
    /// there, and forgetting it would delete a conversation in progress.
    public static func refusal(_ session: Session, harnessTree: String?, cutTree: String?) -> String? {
        let label = session.name.map { "\(session.id) (\($0))" } ?? session.id
        guard session.kind == .background else {
            return "\(label) is an interactive session; the daemon has no row of it to drop"
        }
        switch session.state {
        case .done, .stopped, .failed: break
        case .working, .blocked, .none:
            return "\(label) is \(session.state?.rawValue ?? "in an unknown state"); forget drops finished rows — `ccc stop \(session.id)` first"
        }
        if session.pid != nil || session.status != nil {
            let pid = session.pid.map { " (pid \($0))" } ?? ""
            return "\(label) still has a process\(pid); forget drops finished rows — `ccc stop \(session.id)` first"
        }
        if let harnessTree {
            return "\(label) owns the worktree \(harnessTree) — the harness cut it, so `claude rm` would remove it; `ccc rm \(session.id)` is the verb that takes it"
        }
        if let cutTree {
            return "\(label) stands on \(cutTree), a worktree ccc cut, which `ccc rm` would remove; `ccc rm \(session.id)` is the verb that takes it"
        }
        return nil
    }
}

extension ClaudeCLI {
    public struct ForgetResult: Codable, Sendable {
        public var ref: String
        /// Whether the row is gone. False on a refusal, ours or the harness's.
        public var forgotten: Bool
        /// What was said: the refusal, or the harness's own answer.
        public var said: String

        public init(ref: String, forgotten: Bool, said: String) {
            self.ref = ref
            self.forgotten = forgotten
            self.said = said
        }
    }

    public enum ForgetError: Error, CustomStringConvertible {
        case noRemoteCCC(String)
        public var description: String {
            switch self {
            case .noRemoteCCC(let host):
                return "\(host) has no ccc to check what `claude rm` would take there (`ccc hosts add \(host)` finds one); `ccc rm` is the unguarded verb"
            }
        }
    }

    /// Drop a finished row and keep its tree. Local: the roster read, the
    /// job file, the `ccc-cut` record, then `claude rm` only when all three
    /// say nothing else goes. Remote: the far side's own `ccc forget` —
    /// the job file and the git records are over there, and a remote
    /// forget without them would be an unguarded `rm`, so there is no
    /// passthrough fallback.
    public func forget(id: String, jobsDirectory: URL = DraftProbe.defaultJobsDirectory) async throws -> ForgetResult {
        guard host.isLocal else {
            guard let ccc = host.ccc, let destination = host.ssh else { throw ForgetError.noRemoteCCC(host.name) }
            try prepareControlDirectory()
            let result = try await run(sshPrefix(tty: false, destination: destination) + [ccc, "forget", id, "--json"],
                                       accepting: [0, 1], program: "ccc")
            if let answer = try? JSONDecoder().decode(ForgetResult.self, from: result.stdout) { return answer }
            let said = (String(decoding: result.stdout, as: UTF8.self) + result.stderr)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ForgetResult(ref: id, forgotten: false, said: said)
        }

        let row = try RosterDecoder.decode(try await agentsJSON()).sessions.session(matching: id)
        let harnessTree = ForgetGuard.harnessWorktree(forJob: row.id, jobsDirectory: jobsDirectory)
        let cutTree = WorktreeProbe.cut(at: row.cwd)?.path
        if let reason = ForgetGuard.refusal(row, harnessTree: harnessTree, cutTree: cutTree) {
            return ForgetResult(ref: row.id, forgotten: false, said: reason)
        }
        let result = try await run(rmArgv(id: row.id), accepting: [0, 1], program: "claude")
        let said = (String(decoding: result.stdout, as: UTF8.self) + result.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ForgetResult(ref: row.id, forgotten: result.status == 0, said: said)
    }
}
