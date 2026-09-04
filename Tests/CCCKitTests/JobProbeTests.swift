import Foundation
import Testing
@testable import CCCKit

/// The job join (v10) and what the banner makes of it. The shapes here are
/// the daemon's real ones, copied from `~/.claude/jobs/*/state.json` on
/// studio 2026-09-04 — including the ragged one, which is the whole reason
/// `looksClipped` exists.
@Suite struct JobProbeTests {
    /// The blocked session that started this: the roster row carried **no**
    /// `waitingFor`, and the job file held both the question and a
    /// proposed answer.
    static let blockedJSON = """
    {
      "state": "blocked",
      "detail": "prod), and do you want fake captures to carry the card too so auth→capture flows are testable on staging?",
      "needs": "prod), and do you want fake captures to carry the card too so auth→capture flows are testable on staging?",
      "suggestedReply": "yes go ahead, include the fake capture piece",
      "output": null,
      "children": [
        {"id": "4908", "href": "https://github.com/cuanto-app/cuanto/pull/4908", "kind": "pr"},
        {"id": "4909", "href": "https://github.com/cuanto-app/cuanto/pull/4909", "kind": "pr"}
      ],
      "tokens": 51937
    }
    """

    static let doneJSON = """
    {
      "state": "done",
      "detail": "a stale progress line",
      "output": {"result": "Bugs 2 and 3 fixed and shipped as PRs #4917 and #4916."},
      "children": [
        {"id": "4916", "kind": "pr"},
        {"id": "4917", "kind": "pr"},
        {"id": "carto-options.html", "kind": "frame", "title": "Life After Carto"}
      ]
    }
    """

    @Test func theQuestionComesOffTheJobFileWhenTheRosterHasNone() {
        let job = JobInfo.decode(Data(Self.blockedJSON.utf8))
        #expect(job?.needs?.hasSuffix("testable on staging?") == true)
        #expect(job?.suggestedReply == "yes go ahead, include the fake capture piece")
        #expect(job?.say(for: .blocked) == job?.needs)
    }

    /// `output.result` is the finished word and beats a `detail` left over
    /// from before the session ended — measured, they disagree in 3 of 15.
    @Test func theResultBeatsAStaleDetail() {
        let job = JobInfo.decode(Data(Self.doneJSON.utf8))
        #expect(job?.say(for: .done) == "Bugs 2 and 3 fixed and shipped as PRs #4917 and #4916.")
        #expect(job?.say(for: .working) == "a stale progress line")
    }

    @Test func theReceiptNamesFramesByTitleAndNeverAPR() {
        let job = JobInfo.decode(Data(Self.doneJSON.utf8))
        // The two PRs are in `children` and out of the line — and the
        // sentence below it still names them, with the context a bare
        // number lacks.
        #expect(job?.children.count == 3)
        #expect(job?.receipt == "Life After Carto")
        #expect(job?.say(for: .done)?.contains("#4917") == true)
    }

    /// The number is dropped, not merely deprioritised. Measured
    /// 2026-09-04 across every PR ccc has ever had to draw (171 of them):
    /// 84% merged, 8% closed, and only 25% still open at the instant the
    /// banner drew it — 21% if the *newest* four are taken instead, which
    /// is why recency was not the fix. `children` also spans repos, so the
    /// token was never an address: this is the real `centaur cuanto`
    /// shape, four different PRs in three repos.
    @Test func aPullRequestIsNeverDrawn() {
        let acrossRepos = ["1", "1", "2", "3"].map { JobInfo.Link(id: $0, kind: "pr") }
        #expect(JobInfo(children: acrossRepos).receipt == nil)
        #expect(JobInfo().receipt == nil)
    }

    /// A session with eleven artifacts must not spend the whole line on a
    /// list nobody reads to the end — and the `+N` counts what was
    /// eligible, never the PRs that were dropped before the cap.
    @Test func theReceiptStopsAtFourAndCountsTheRest() {
        let frames = (1...7).map { JobInfo.Link(id: "f\($0)", kind: "frame", title: "Frame \($0)") }
        #expect(JobInfo(children: frames).receipt == "Frame 1 · Frame 2 · Frame 3 · Frame 4 +3")
        let buried = (1...40).map { JobInfo.Link(id: "\($0)", kind: "pr") } + frames.prefix(5)
        #expect(JobInfo(children: buried).receipt == "Frame 1 · Frame 2 · Frame 3 · Frame 4 +1")
    }

    /// An unknown kind is not a PR, so it passes through — the boundary
    /// stays lenient in the direction of showing what it was given.
    @Test func anUnknownKindStillGetsNamed() {
        #expect(JobInfo(children: [.init(id: "deploy-7", kind: "release")]).receipt == "deploy-7")
        #expect(JobInfo(children: [.init(id: "x", kind: nil, title: "Untyped")]).receipt == "Untyped")
    }

    /// The boundary rule (CLAUDE.md): a wrong type is a dropped field, not
    /// a failed reading, and a payload that is not an object is `nil`.
    @Test func aWrongTypeIsDroppedAndTheRestSurvives() {
        let json = #"{"detail": 42, "needs": "the real question", "children": "not a list"}"#
        let job = JobInfo.decode(Data(json.utf8))
        #expect(job?.detail == nil)
        #expect(job?.needs == "the real question")
        #expect(job?.children.isEmpty == true)
        #expect(JobInfo.decode(Data("[]".utf8)) == nil)
        #expect(JobInfo.decode(Data("not json".utf8)) == nil)
    }

    /// Nothing to say is `nil`, not an empty reading — a row's `job` is
    /// present only when it carries something.
    @Test func aFileWithNothingUsableIsNoReadingAtAll() {
        #expect(JobInfo.decode(Data(#"{"state": "done", "tokens": 5}"#.utf8)) == nil)
        #expect(JobInfo.decode(Data(#"{"detail": "   "}"#.utf8)) == nil)
    }

    /// A PR id arrives as a number in some shapes; both spellings decode.
    /// It is not drawn either way, but a dropped *field* and a dropped
    /// *number* are different failures and only one of them is intended.
    @Test func aNumericChildIdStillDecodes() {
        let job = JobInfo.decode(Data(#"{"children": [{"id": 4899, "kind": "pr"}]}"#.utf8))
        #expect(job?.children == [.init(id: "4899", kind: "pr")])
        #expect(job?.receipt == nil)
    }

    // MARK: what the banner says

    private func event(_ kind: SessionEvent.Kind, name: String, waitingFor: String? = nil,
                       job: JobInfo?) -> SessionEvent {
        SessionEvent(kind: kind, ref: SessionRef(host: "studio", id: "abc123"), name: name,
                     waitingFor: waitingFor, job: job, at: Date())
    }

    /// The daemon's extraction is ragged. A fragment gets a leading
    /// ellipsis so it reads as deliberate rather than broken.
    @Test func aClippedQuestionIsMarkedAsOne() {
        let job = JobInfo.decode(Data(Self.blockedJSON.utf8))
        let e = event(.blocked, name: "linear cuanto bill project", job: job)
        #expect(e.body?.hasPrefix("…prod), and do you want") == true)
        #expect(SessionEvent.looksClipped("prod), and do you") == true)
        // Lowercase is the normal register for a `detail`, not damage —
        // these are all real ones, and none of them is a fragment.
        #expect(SessionEvent.looksClipped("wiki: TCC identity fix scoped") == false)
        #expect(SessionEvent.looksClipped("detour arithmetic verified; awaiting capture (300/16 MB)") == false)
        #expect(SessionEvent.looksClipped("keyboards (K400 Plus + K600 TV), smart plugs (Shelly)") == false)
        #expect(SessionEvent.looksClipped("answer: Should the banner show the branch? (Yes · No)") == false)
        #expect(SessionEvent.looksClipped("Bugs 2 and 3 fixed") == false)
        // An unmatched *opener* is a cut tail, which is macOS's job.
        #expect(SessionEvent.looksClipped("Carto watermark root-caused (a vendor") == false)
    }

    /// The job file beats `waitingFor`, found the hard way: a fixture
    /// blocked on `AskUserQuestion` answered `waitingFor: "input needed"`
    /// — a placeholder — while its job file held the actual question. The
    /// roster's word is the fallback, for a session with no job file.
    @Test func theJobFileBeatsAPlaceholder() {
        let asking = JobInfo(needs: "answer: Should the banner show the branch? (Yes · No)")
        #expect(event(.blocked, name: "a", waitingFor: "input needed", job: asking).body
                == "answer: Should the banner show the branch? (Yes · No)")
        // No job file at all: the roster's word is all there is.
        #expect(event(.blocked, name: "a", waitingFor: "approve rm -rf?", job: nil).body == "approve rm -rf?")
        #expect(event(.blocked, name: "a", job: nil).body == nil)
        // An ending never borrows `waitingFor` — it is a blocked concept.
        #expect(event(.done, name: "a", waitingFor: "input needed", job: nil).body == nil)
    }

    /// Mid-question is not the moment to list what came out.
    @Test func theReceiptIsForEndingsOnly() {
        let job = JobInfo.decode(Data(Self.blockedJSON.utf8))
        #expect(event(.blocked, name: "a", job: job).receipt == nil)
        #expect(event(.done, name: "a", job: JobInfo.decode(Data(Self.doneJSON.utf8))).receipt
                == "Life After Carto")
    }

    /// The host goes last so the ellipsis eats it and not the name, and it
    /// is drawn at all only when the fleet is plural.
    @Test func theHostRidesTheTailOfTheTitle() {
        let e = event(.blocked, name: "linear cuanto bill project", job: nil)
        #expect(e.title(showingHost: false) == "✋ linear cuanto bill project")
        #expect(e.title(showingHost: true) == "✋ linear cuanto bill project · studio")
        #expect(event(.done, name: "cdn", job: nil).title(showingHost: false) == "✓ cdn")
    }

    /// `ccc watch` keeps its sentence — its `kind` column makes the verb
    /// redundant, but a log line reads as prose — and gains the payload
    /// without repeating what the sentence already carried.
    /// This line is what named the cost: the old bracket read
    /// `[#4916 · #4917 · Life After Carto]` under a sentence that had
    /// **already** said #4917 and #4916, so the test's own title was the
    /// argument against it.
    @Test func theWatchLineSaysEachThingOnce() {
        let job = JobInfo.decode(Data(Self.doneJSON.utf8))
        #expect(event(.done, name: "debug cuanto", job: job).watchLine
                == "debug cuanto finished — Bugs 2 and 3 fixed and shipped as PRs #4917 and #4916.  [Life After Carto]")
        // waitingFor is already in the headline, so it is not said twice.
        #expect(event(.blocked, name: "a", waitingFor: "approve rm -rf?", job: nil).watchLine
                == "a is waiting: approve rm -rf?")
    }

    // MARK: what the row says (slice 2)

    private func row(_ state: Session.State?, job: JobInfo?, draft: Bool = false) -> SessionRow {
        SessionRow(session: Session(id: "abc123", cwd: "/x", kind: .background, startedAt: Date(), state: state),
                   host: "studio", model: nil, attached: false, draft: draft, job: job)
    }

    /// The roster row gains the field the banner could never carry:
    /// `detail` narrates a **working** session, and working is the one
    /// state ccc never notifies on.
    @Test func theRowSaysWhatAWorkingSessionIsDoing() {
        let working = JobInfo(detail: "detour arithmetic verified; awaiting capture (300/16 MB)")
        #expect(row(.working, job: working).say == "detour arithmetic verified; awaiting capture (300/16 MB)")
        #expect(row(.done, job: JobInfo.decode(Data(Self.doneJSON.utf8))).say
                == "Bugs 2 and 3 fixed and shipped as PRs #4917 and #4916.")
        #expect(row(.working, job: nil).say == nil)
    }

    /// A draft says nothing: its `needs` is the harness's own "send a
    /// prompt to start", which the row already tells you by being a draft.
    @Test func aDraftSaysNothing() {
        let unprompted = JobInfo(detail: DraftProbe.needsPhrase, needs: DraftProbe.needsPhrase)
        #expect(row(.blocked, job: unprompted, draft: true).say == nil)
        // The same file on a row the draft reading did not claim still
        // speaks — the suppression is about the draft, not the phrase.
        #expect(row(.blocked, job: unprompted).say == DraftProbe.needsPhrase)
    }

    // MARK: the probe on disk

    @Test func anUnchangedJobFileCostsAStatAndNoRead() throws {
        let dir = URL.temporaryDirectory.appending(path: "ccc-jobs-\(UUID().uuidString)")
        let job = dir.appending(path: "abc123")
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
        try Data(Self.doneJSON.utf8).write(to: job.appending(path: "state.json"))
        defer { try? FileManager.default.removeItem(at: dir) }

        let probe = JobProbe(jobsDirectory: dir)
        #expect(probe.info(forJob: "abc123")?.receipt == "Life After Carto")
        #expect(probe.stats == JobProbe.Counters(reads: 1, hits: 0, misses: 0))
        for _ in 0..<5 { _ = probe.info(forJob: "abc123") }
        #expect(probe.stats == JobProbe.Counters(reads: 1, hits: 5, misses: 0))
        // An interactive session has no job directory at all.
        #expect(probe.info(forJob: "nosuch") == nil)
        #expect(probe.stats.misses == 1)
    }

    /// The draft reading (v5) now rides the parsed file instead of opening
    /// it a second time, and must not have changed its mind about anything.
    @Test func theDraftReadingAgreesWithItsOlderSelf() {
        let unprompted = Data(#"{"needs": "send a prompt to start"}"#.utf8)
        let asking = Data(Self.blockedJSON.utf8)
        for data in [unprompted, asking] {
            let viaFile = DraftProbe.reading(fromStateJSON: data)
            let viaJob = JobInfo.decode(data).flatMap(DraftProbe.reading(from:))
            #expect(viaFile == viaJob)
        }
        #expect(DraftProbe.reading(from: JobInfo(needs: "send a prompt to start")) == true)
        #expect(DraftProbe.reading(from: JobInfo(detail: "something else")) == false)
        #expect(DraftProbe.reading(from: JobInfo(children: [.init(id: "1")])) == nil)
    }

    /// Like the model and the worktree before it, the reading is joined
    /// where the daemon's files are and rides the row across the hop —
    /// and an older ccc on the far side simply sends no `job` key.
    @Test func theRowCarriesTheJobAcrossTheWire() throws {
        let session = Session(id: "abc123", cwd: "/x", kind: .background, startedAt: Date(), state: .blocked)
        let row = SessionRow(session: session, host: "studio", model: nil, attached: false,
                             job: JobInfo.decode(Data(Self.blockedJSON.utf8)))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let back = try JSONDecoder.roster.decode(SessionRow.self, from: encoder.encode(row))
        #expect(back.job?.suggestedReply == "yes go ahead, include the fake capture piece")
        // `children` crosses whole — it is the archive, and what the far
        // side draws from it is the near side's decision, not the wire's.
        #expect(back.job?.children.count == 2)
        #expect(back.job?.receipt == nil)

        // An older ccc on the far side sends the same row without the key.
        var older = try #require(try JSONSerialization.jsonObject(with: encoder.encode(row)) as? [String: Any])
        older.removeValue(forKey: "job")
        let wire = try JSONSerialization.data(withJSONObject: older)
        #expect(try JSONDecoder.roster.decode(SessionRow.self, from: wire).job == nil)
    }
}
