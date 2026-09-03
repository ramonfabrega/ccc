import Foundation
import Testing

@testable import CCCKit

/// v5's draft reading: a never-prompted session is `blocked · idle` to the
/// harness and "yours to start" to us. The signal is the daemon's job
/// file (recorded 2026-09-02 from a real draft and a real question), the
/// fallback is the transcript's absence, and every face that says "your
/// turn" leaves a draft out.
@Suite struct DraftTests {
    /// `~/.claude/jobs/59a93d74/state.json` for a `claude --bg --name x`
    /// with no prompt, trimmed to the fields that matter.
    static let draftState = #"{"state":"working","detail":"(idle — send a prompt to start)","tempo":"blocked","needs":"send a prompt to start","output":null,"intent":"","name":"ccc-v5-draftcheck","sessionId":"59a93d74-b557-4904-b506-7a8d78c4417b","firstTerminalAt":null}"#
    /// The same file for a session blocked on an AskUserQuestion.
    static let questionState = #"{"state":"blocked","detail":"prod), and do you want fake captures…","tempo":"blocked","tokens":51937,"needs":"prod), and do you want fake captures to carry the card too?","intent":"lets orient ourselves"}"#

    private func session(_ state: Session.State? = .blocked, status: Session.Status? = .idle,
                         waitingFor: String? = nil, kind: Session.Kind = .background, id: String = "a") -> Session {
        Session(id: id, cwd: "/x", kind: kind, startedAt: Date(timeIntervalSince1970: 0),
                state: state, status: status, pid: 1, waitingFor: waitingFor, sessionId: "\(id)-uuid", name: id)
    }

    private func jobs(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "ccc-draft-\(UUID().uuidString)")
        for (id, json) in files {
            let dir = root.appending(path: id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: dir.appending(path: "state.json"))
        }
        return root
    }

    // MARK: the reading

    @Test func theDaemonsOwnPhraseSettlesIt() {
        #expect(DraftProbe.reading(fromStateJSON: Data(Self.draftState.utf8)) == true)
        #expect(DraftProbe.reading(fromStateJSON: Data(Self.questionState.utf8)) == false)
    }

    @Test func aFileThatSaysNothingUsableIsNoReading() {
        #expect(DraftProbe.reading(fromStateJSON: Data("{}".utf8)) == nil)
        #expect(DraftProbe.reading(fromStateJSON: Data("not json".utf8)) == nil)
        #expect(DraftProbe.reading(fromStateJSON: Data(#"{"needs": 7}"#.utf8)) == nil)
        // `detail` alone carries the phrase too.
        #expect(DraftProbe.reading(fromStateJSON: Data(#"{"detail":"(idle — send a prompt to start)"}"#.utf8)) == true)
    }

    @Test func onlyABlockedIdleBackgroundRowCanBeADraft() {
        #expect(DraftProbe.couldBeDraft(session()))
        #expect(DraftProbe.couldBeDraft(session(status: nil)))
        #expect(!DraftProbe.couldBeDraft(session(.working, status: .busy)))
        #expect(!DraftProbe.couldBeDraft(session(.done)))
        #expect(!DraftProbe.couldBeDraft(session(waitingFor: "approve rm?")), "a question is never a draft")
        #expect(!DraftProbe.couldBeDraft(session(status: .waiting)))
        #expect(!DraftProbe.couldBeDraft(session(kind: .interactive)))
    }

    @Test func theJobFileWinsAndTheTranscriptIsTheFallback() throws {
        let dir = try jobs(["a": Self.draftState, "b": Self.questionState, "c": "{}"])
        defer { try? FileManager.default.removeItem(at: dir) }
        // The file settles it either way, whatever the transcript says.
        #expect(DraftProbe.isDraft(session(id: "a"), transcriptFound: true, jobsDirectory: dir))
        #expect(!DraftProbe.isDraft(session(id: "b"), transcriptFound: false, jobsDirectory: dir))
        // No usable file: a session with no transcript was never prompted.
        #expect(DraftProbe.isDraft(session(id: "c"), transcriptFound: false, jobsDirectory: dir))
        #expect(!DraftProbe.isDraft(session(id: "c"), transcriptFound: true, jobsDirectory: dir))
        // No file at all: the same fallback.
        #expect(DraftProbe.isDraft(session(id: "zzz"), transcriptFound: false, jobsDirectory: dir))
        // The file is never consulted for a row that cannot be a draft.
        #expect(!DraftProbe.isDraft(session(.working, status: .busy, id: "a"), transcriptFound: false, jobsDirectory: dir))
    }

    // MARK: the row

    @Test func aDraftIsNotYourTurn() {
        let draft = SessionRow(session: session(), model: nil, attached: false, draft: true)
        let question = SessionRow(session: session(), model: nil, attached: false)
        #expect(!draft.isWaiting)
        #expect(question.isWaiting)
        // Archived: the question stays visible (v4's rule), the draft folds.
        var archivedDraft = draft
        archivedDraft.archived = true
        var archivedQuestion = question
        archivedQuestion.archived = true
        #expect(archivedDraft.isHidden)
        #expect(!archivedQuestion.isHidden)
    }

    @Test func aDraftSortsBelowLiveWorkAndAboveTheFinished() {
        let draft = SessionRow(session: session(id: "d"), model: nil, attached: false, draft: true)
        let question = SessionRow(session: session(id: "q"), model: nil, attached: false)
        let working = SessionRow(session: session(.working, status: .busy, id: "w"), model: nil, attached: false)
        let done = SessionRow(session: session(.done, id: "f"), model: nil, attached: false)
        var poll = HostPoll(host: Host.localName)
        poll.rows = [done, draft, working, question]
        poll.pollCount = 1
        let state = RosterPoller.State(hosts: [poll])
        #expect(state.rows(sortedBy: .activity).map(\.session.id) == ["q", "w", "d", "f"])
        let sections = state.sections(group: .state, sort: .activity, archived: false)
        #expect(sections.map(\.title) == ["waiting", "working", "drafts", "finished"])
        #expect(sections[2].rows.map(\.session.id) == ["d"])
    }

    /// The flag rides `ccc list --json` like the model and the marks, and
    /// an older far side that has never heard of it reads as no draft.
    @Test func theFlagCrossesTheHopAndDefaultsOff() throws {
        let row = SessionRow(session: session(), host: "studio", model: nil, attached: false, draft: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([row])
        #expect(try JSONDecoder.roster.decode([SessionRow].self, from: data).first?.draft == true)
        let older = #"[{"session":{"id":"a","cwd":"/x","kind":"background","startedAt":"2026-09-02T00:00:00Z","state":"blocked","status":"idle","extra":{}},"host":"studio","attached":false}]"#
        let decoded = try JSONDecoder.roster.decode([SessionRow].self, from: Data(older.utf8))
        #expect(decoded.first?.draft == false)
        #expect(decoded.first?.isWaiting == true)
    }

    // MARK: the detector

    private func poll(_ rows: [SessionRow], count: Int = 1) -> HostPoll {
        var p = HostPoll(host: Host.localName)
        p.rows = rows
        p.pollCount = count
        return p
    }

    @Test func aFreshDraftIsNotAnEventButItsFirstQuestionIs() {
        var d = TransitionDetector()
        _ = d.observe(.init(hosts: [poll([])]))
        let draft = SessionRow(session: session(), model: nil, attached: false, draft: true)
        #expect(d.observe(.init(hosts: [poll([draft])])).isEmpty, "a draft appearing is not your turn")
        // Prompted: working, then blocked on a waitingFor-less question.
        let working = SessionRow(session: session(.working, status: .busy), model: nil, attached: false)
        #expect(d.observe(.init(hosts: [poll([working])])).isEmpty)
        let question = SessionRow(session: session(), model: nil, attached: false)
        #expect(d.observe(.init(hosts: [poll([question])])).map(\.kind) == [.blocked])
    }

    /// The edge the key exists for: the draft's row and the question's row
    /// are identical to the harness (`blocked · idle`, no `waitingFor`).
    /// Without `draft` in the key, the question would be silent.
    @Test func aDraftThatBecomesAQuestionWithoutPassingThroughWorkingStillRings() {
        var d = TransitionDetector()
        let draft = SessionRow(session: session(), model: nil, attached: false, draft: true)
        _ = d.observe(.init(hosts: [poll([draft])]))
        let question = SessionRow(session: session(), model: nil, attached: false)
        #expect(d.observe(.init(hosts: [poll([question])])).map(\.kind) == [.blocked])
    }
}
