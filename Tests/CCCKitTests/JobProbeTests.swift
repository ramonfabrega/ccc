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

    /// The boundary rule (CLAUDE.md): a wrong type is a dropped field, not
    /// a failed reading, and a payload that is not an object is `nil`.
    @Test func aWrongTypeIsDroppedAndTheRestSurvives() {
        let json = #"{"detail": 42, "needs": "the real question", "children": "not a list"}"#
        let job = JobInfo.decode(Data(json.utf8))
        #expect(job?.detail == nil)
        #expect(job?.needs == "the real question")
        #expect(JobInfo.decode(Data("[]".utf8)) == nil)
        #expect(JobInfo.decode(Data("not json".utf8)) == nil)
    }

    /// `children` is not read at all (v11 slice 4). The two fixtures above
    /// still carry theirs verbatim, which is the point: an unread field is
    /// stepped over, never a reason to fail — and a file whose only
    /// content is one is no reading, the same as an empty one.
    @Test func theLinksAreSteppedOverEntirely() {
        let onlyLinks = #"{"children": [{"id": 4899, "kind": "pr"}, {"id": "a.html", "kind": "frame"}]}"#
        #expect(JobInfo.decode(Data(onlyLinks.utf8)) == nil)
        // And their presence does not disturb the fields that are read.
        #expect(JobInfo.decode(Data(Self.doneJSON.utf8))?.detail == "a stale progress line")
    }

    /// Nothing to say is `nil`, not an empty reading — a row's `job` is
    /// present only when it carries something.
    @Test func aFileWithNothingUsableIsNoReadingAtAll() {
        #expect(JobInfo.decode(Data(#"{"state": "done", "tokens": 5}"#.utf8)) == nil)
        #expect(JobInfo.decode(Data(#"{"detail": "   "}"#.utf8)) == nil)
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

    /// The host goes last so the ellipsis eats it and not the name, and it
    /// is drawn at all only when the fleet is plural.
    @Test func theHostRidesTheTailOfTheTitle() {
        let e = event(.blocked, name: "linear cuanto bill project", job: nil)
        #expect(e.title(showingHost: false) == "✋ linear cuanto bill project")
        #expect(e.title(showingHost: true) == "✋ linear cuanto bill project · studio")
        #expect(event(.done, name: "cdn", job: nil).title(showingHost: false) == "✓ cdn")
    }

    /// `ccc watch` keeps its sentence — its `kind` column makes the verb
    /// redundant, but a log line reads as prose — and says each thing
    /// once. This line is what named the cost of the receipt: the bracket
    /// read `[#4916 · #4917 · Life After Carto]` under a sentence that had
    /// **already** said #4917 and #4916, so the test's own title was the
    /// argument against it. The banner and this line lost it together —
    /// one definition, many surfaces (CLAUDE.md).
    @Test func theWatchLineSaysEachThingOnce() {
        let job = JobInfo.decode(Data(Self.doneJSON.utf8))
        #expect(event(.done, name: "debug cuanto", job: job).watchLine
                == "debug cuanto finished — Bugs 2 and 3 fixed and shipped as PRs #4917 and #4916.")
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
        #expect(probe.info(forJob: "abc123")?.say(for: .done)?.hasPrefix("Bugs 2 and 3") == true)
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
        #expect(DraftProbe.reading(from: JobInfo(suggestedReply: "no phrase here")) == nil)
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
        #expect(back.job?.say(for: .blocked)?.hasSuffix("testable on staging?") == true)

        // An older ccc on the far side sends the same row without the key.
        var older = try #require(try JSONSerialization.jsonObject(with: encoder.encode(row)) as? [String: Any])
        older.removeValue(forKey: "job")
        let wire = try JSONSerialization.data(withJSONObject: older)
        #expect(try JSONDecoder.roster.decode(SessionRow.self, from: wire).job == nil)
    }
}

/// Remote Control off the job file (item 17). The shapes are studio's real
/// `respawnFlags`, copied 2026-09-04 — the fleet writes `--rc` and the
/// ad-hoc `--agent claude` spawns do not, which is the whole discrimination.
@Suite struct JobRemoteControlTests {
    /// `--rc` among the flags, in the position the daemon actually writes
    /// it: first, with the name and model after.
    @Test func theFlagIsRead() {
        let json = #"{"state":"blocked","detail":"x","respawnFlags":["--rc","--name","ccc","--model","opus[1m]"]}"#
        #expect(JobInfo.decode(Data(json.utf8))?.remoteControl == true)
    }

    /// The long spelling the harness also accepts. The fleet does not write
    /// it, which is exactly why it is tested: nothing else would catch a
    /// session that *is* answerable from the phone reading as one that is
    /// not.
    @Test func theLongSpellingCounts() {
        let json = #"{"detail":"x","respawnFlags":["--name","n","--remote-control"]}"#
        #expect(JobInfo.decode(Data(json.utf8))?.remoteControl == true)
    }

    /// An ad-hoc spawn: flags, none of them `--rc`.
    @Test func anOrdinarySpawnIsNotRemoteControlled() {
        let json = #"{"detail":"x","respawnFlags":["--agent","claude","--model","opus[1m]"]}"#
        #expect(JobInfo.decode(Data(json.utf8))?.remoteControl == false)
    }

    /// Lenient like every other boundary reading: a missing key, a wrong
    /// type, and wrong element types all answer "not remote-controlled"
    /// rather than throwing or claiming reachability the row cannot back.
    @Test func aChangedShapeIsNotRemoteControlled() {
        for flags in ["null", #""--rc""#, "5", #"[1,2,3]"#, #"[{"a":"--rc"}]"#] {
            let json = #"{"detail":"x","respawnFlags":\#(flags)}"#
            #expect(JobInfo.decode(Data(json.utf8))?.remoteControl == false, "flags: \(flags)")
        }
        #expect(JobInfo.decode(Data(#"{"detail":"x"}"#.utf8))?.remoteControl == false)
    }

    /// `--rc` alone is a reading worth carrying: a session with nothing to
    /// say but a phone it can be answered from is not the empty reading.
    @Test func theFlagAloneSurvivesTheEmptyCheck() {
        let json = #"{"state":"working","respawnFlags":["--rc"]}"#
        let info = JobInfo.decode(Data(json.utf8))
        #expect(info?.remoteControl == true)
        #expect(info?.say(for: .working) == nil)
        // …and a job file with neither a sentence nor the flag is still nil.
        #expect(JobInfo.decode(Data(#"{"state":"done","respawnFlags":["--agent","claude"]}"#.utf8)) == nil)
    }

    /// The hop, which is the reason `JobInfo` decodes by hand. A reading
    /// from an **older ccc** carries no `remoteControl` key; the newest
    /// field must fall back to false without taking `detail`, `needs` and
    /// `result` down with it, because `SessionRow` decodes the whole
    /// reading with `try?` and would drop it whole.
    @Test func anOlderCccsReadingKeepsItsSentence() throws {
        let wire = #"{"detail":"live line","needs":"a question","result":"a result"}"#
        let info = try JSONDecoder().decode(JobInfo.self, from: Data(wire.utf8))
        #expect(info.remoteControl == false)
        #expect(info.detail == "live line")
        #expect(info.needs == "a question")
        #expect(info.result == "a result")
    }

    /// And the round trip this build writes for the next one.
    @Test func theFlagCrossesTheHop() throws {
        let sent = JobInfo(detail: "d", remoteControl: true)
        let data = try JSONEncoder().encode(sent)
        #expect(try JSONDecoder().decode(JobInfo.self, from: data) == sent)
    }
}
