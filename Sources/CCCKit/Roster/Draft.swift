import Foundation

/// A draft is a background session that has never been given a prompt
/// (v5): `claude --bg` with nothing to do, sitting at the harness's
/// prompt. The roster cannot tell it from a session asking a question —
/// both are `blocked · idle`, and neither carries `waitingFor` when the
/// question came from AskUserQuestion (docs/HARNESS.md) — so the reading
/// is joined where the daemon's files are, like the model column, and
/// rides the far side's `ccc list --json` row.
///
/// The signal is the daemon's own: `~/.claude/jobs/<id>/state.json` says
/// `needs: "send a prompt to start"`, the phrase `--bg` itself printed.
/// Read leniently (the file is undocumented past "unknown fields are
/// preserved"), and only ever *read* (CLAUDE.md: never write under
/// `~/.claude/jobs`). When the file cannot be read or has no `needs`, the
/// fallback is the transcript: a session that was never prompted has
/// none, a session that asked a question has one.
public enum DraftProbe {
    /// The daemon's phrase for it — the same words in the `--bg` answer.
    public static let needsPhrase = "send a prompt to start"

    public static var defaultJobsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/jobs")
    }

    /// Does the row's state even allow a draft? Cheap; the file is only
    /// opened when this says yes.
    public static func couldBeDraft(_ session: Session) -> Bool {
        session.kind == .background && session.state == .blocked
            && (session.status == .idle || session.status == nil)
            && (session.waitingFor ?? "").isEmpty
    }

    /// What `state.json` says, if anything: `true` / `false` when its
    /// `needs` field settles it, `nil` when the file is missing or says
    /// nothing usable — the fallback's case.
    public static func reading(fromStateJSON data: Data) -> Bool? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let needs = object["needs"] as? String {
            return needs.contains(needsPhrase)
        }
        if let detail = object["detail"] as? String {
            return detail.contains(needsPhrase)
        }
        return nil
    }

    /// The same reading against an already-parsed job file (v10). The
    /// poller opens `state.json` once per row for `JobProbe` and hands the
    /// result here, so the draft reading costs no second read.
    public static func reading(from job: JobInfo) -> Bool? {
        if let needs = job.needs { return needs.contains(needsPhrase) }
        if let detail = job.detail { return detail.contains(needsPhrase) }
        return nil
    }

    /// The full reading for one local row. `transcriptFound` is the model
    /// join's answer for the same row, so the fallback costs nothing extra.
    public static func isDraft(_ session: Session, job: JobInfo?, transcriptFound: Bool) -> Bool {
        guard couldBeDraft(session) else { return false }
        if let job, let settled = reading(from: job) { return settled }
        return !transcriptFound
    }

    /// The reading straight off disk, for callers with no `JobProbe` —
    /// `ccc list` in a one-shot, and the tests that pin the phrase.
    public static func isDraft(_ session: Session, transcriptFound: Bool,
                               jobsDirectory: URL = defaultJobsDirectory) -> Bool {
        guard couldBeDraft(session) else { return false }
        let file = jobsDirectory.appending(path: session.id).appending(path: "state.json")
        if let data = try? Data(contentsOf: file), let settled = reading(fromStateJSON: data) {
            return settled
        }
        return !transcriptFound
    }
}
