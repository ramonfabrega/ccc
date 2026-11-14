import Foundation

/// **One session, in full** — what the reading pane draws and `ccc show`
/// prints (2026-11-13).
///
/// The roster row is ~400 pt wide and every line of it is cut to fit: the
/// daemon's sentence at about sixty characters where a finished result
/// runs to 460, the branch squeezed to `w…-4222` beside a folder five rows
/// share, the worktree's standing and the full path behind tooltips, and
/// `suggestedReply` read from the job file and drawn nowhere. Meanwhile
/// the pane to its right — two thirds of the window — said one sentence
/// whenever nothing was attached. This is the row with the cuts taken
/// out, for the space that had nothing in it.
///
/// A pure function of the row, like `SessionRow.say`: the window and the
/// command line build it from the same roster and so cannot disagree
/// (CLAUDE.md, one definition, many surfaces). Nothing here reads a file
/// or asks the harness anything the poll did not already answer.
///
/// **What is left out is the design.** The first thing in it is the thing
/// to act on — the question, the result — and the facts under it are only
/// the ones that carry payload for *this* row: a host when there is more
/// than one, Remote Control only when it is off on a live session (the
/// news, per `ccc list --help`), a permission mode only when it will stop
/// the session. A pane with room for everything is how a view becomes
/// "so much text it loses meaning".
public struct SessionDetail: Codable, Sendable, Equatable {
    /// A block of prose: what the session is asking, did, or is doing.
    public struct Passage: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable {
            /// The row's own sentence for its state (`SessionRow.say`).
            case say
            /// The answer the daemon proposes to a question.
            case reply
        }
        public var kind: Kind
        public var title: String
        public var text: String
        public init(kind: Kind, title: String, text: String) {
            self.kind = kind
            self.title = title
            self.text = text
        }
    }

    /// One labelled line. `note` is the second half of the line, quieter:
    /// a branch's standing beside its name.
    public struct Fact: Codable, Sendable, Equatable {
        public var label: String
        public var value: String
        public var note: String?
        /// The unabridged value — a full timestamp behind `17:45` — for a
        /// tooltip and for `--json`.
        public var full: String?
        public init(label: String, value: String, note: String? = nil, full: String? = nil) {
            self.label = label
            self.value = value
            self.note = note
            self.full = full
        }
    }

    public var ref: String
    public var name: String
    /// `SessionRow.stateText` — the row's second line, verbatim.
    public var state: String
    public var tone: SessionRow.Tone
    /// The serving model, `claude-` dropped, as the row prints it.
    public var model: String?
    public var passages: [Passage]
    public var facts: [Fact]
    /// Whether ⏎ does anything: an interactive session cannot be attached.
    public var attachable: Bool

    public init(row: SessionRow, showsHost: Bool = false, now: Date = Date(), calendar: Calendar = .current,
                shortCwd: (String) -> String = { $0 }) {
        let session = row.session
        ref = row.ref.description
        name = session.name ?? session.id
        state = row.stateText
        tone = row.tone
        model = row.model.map { $0.replacingOccurrences(of: "claude-", with: "") }
        attachable = session.isAttachable

        var passages: [Passage] = []
        // A blocked row whose job file says nothing still has the roster's
        // own word for what it waits on.
        let said = row.say ?? (row.isWaiting ? session.waitingFor : nil)
        if let said {
            let title: String
            switch session.state {
            case .blocked: title = "asking"
            case .done: title = "result"
            case .working: title = "doing"
            default: title = "last said"
            }
            passages.append(Passage(kind: .say, title: title, text: said))
        }
        if row.isWaiting, let reply = row.job?.suggestedReply {
            passages.append(Passage(kind: .reply, title: "suggested reply", text: reply))
        }
        // `detail` beside a `needs` or a `result` is **not drawn**. It was,
        // for one build: on a finished row it read "tree 594 tint matches
        // photo; 4221 branch ready, 3 parked" under a result that said the
        // same thing in a sentence. The daemon's live line is a paraphrase
        // of the field the state already has, and a paraphrase is the
        // second copy this pane exists not to print.
        self.passages = passages

        var facts: [Fact] = []
        if let wt = row.worktree {
            // Two lines, not one with a note. On the first released build
            // (v0.1.48) the standing rode beside the branch and the pair
            // overflowed the column, so the ellipsis took the middle —
            // "…-replan-pdb…hed; worktree-replan-pdb has 6 unpushed" — which
            // is exactly the "3 ahead" the line exists to say.
            facts.append(Fact(label: "branch", value: "\(wt.branch) → \(wt.base)"))
            facts.append(Fact(label: "stands", value: wt.standing))
        }
        facts.append(Fact(label: "folder", value: shortCwd(session.cwd), full: session.cwd))
        if showsHost { facts.append(Fact(label: "host", value: row.host)) }
        let iso = ISO8601DateFormatter()
        facts.append(Fact(label: "started", value: Stamp.text(session.startedAt, now: now, calendar: calendar),
                          full: iso.string(from: session.startedAt)))
        if let moved = row.job?.updatedAt {
            facts.append(Fact(label: "moved", value: Stamp.text(moved, now: now, calendar: calendar),
                              full: iso.string(from: moved)))
        }
        if row.lacksRemoteControl {
            facts.append(Fact(label: "answer", value: "only on \(row.host == Host.localName ? "this Mac" : row.host)",
                              note: "dispatched without Remote Control"))
        }
        if session.kind == .background, let job = row.job {
            if job.asksForPermission {
                facts.append(Fact(label: "asks", value: "--permission-mode \(job.permissionMode ?? "?")",
                                  note: "permission prompts block it until answered"))
            }
        }
        if !session.isAttachable {
            facts.append(Fact(label: "kind", value: "interactive", note: "runs in its own terminal; cannot be attached"))
        }
        facts.append(Fact(label: "id", value: row.ref.description, full: session.sessionId))
        self.facts = facts
    }

    /// The command line's rendering: the header, the prose indented under
    /// its title, then the facts in two columns.
    public var text: String {
        var lines = [[name, state, model].compactMap { $0 }.joined(separator: "  ")]
        for passage in passages {
            lines.append("")
            lines.append(passage.title)
            for line in passage.text.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append("  \(line)")
            }
        }
        lines.append("")
        let width = facts.map(\.label.count).max() ?? 0
        for fact in facts {
            let label = fact.label.padding(toLength: width, withPad: " ", startingAt: 0)
            lines.append("\(label)  \(fact.value)" + (fact.note.map { " · \($0)" } ?? ""))
        }
        return lines.joined(separator: "\n")
    }
}

extension SessionRow {
    /// What colour a row is, as a word: the dot, the state line, and the
    /// reading pane's header all read this, so they cannot drift.
    public enum Tone: String, Codable, Sendable {
        /// Never prompted.
        case draft
        /// Blocked on you.
        case waiting
        /// Working, with something live attached.
        case busy
        /// Working, nothing in flight.
        case working
        case failed
        /// Done, process still up.
        case rested
        /// Done or stopped, no process.
        case gone
        /// An interactive session with a process.
        case live
        case unknown
    }

    public var tone: Tone {
        if draft { return .draft }
        switch session.state {
        case .blocked: return .waiting
        case .working: return session.status == .busy ? .busy : .working
        case .failed: return .failed
        case .done: return session.pid != nil ? .rested : .gone
        case .stopped: return .gone
        case nil: return session.pid != nil ? .live : .unknown
        }
    }

    /// The state as the roster row says it, which is only where the dot
    /// does not: green is working and orange is asking, so those say
    /// nothing; grey is both done and stopped, so those say which; a
    /// draft says what it is waiting for. Measured 2026-11-13: the full
    /// `stateText` repeated the dot's colour on 13 rows of 13.
    public var stateWord: String? {
        if draft { return stateText }
        switch session.state {
        case .working: return nil
        // Asking, and the question is on the row. A blocked row with
        // nothing to show for it still has to say so.
        case .blocked: return say == nil && session.waitingFor == nil ? "blocked" : nil
        case .done, .failed, .stopped: return session.state?.rawValue
        case nil: return session.kind.rawValue
        }
    }

    /// A live session that can only be answered at the Mac it runs on.
    /// `ccc spawn` defaults Remote Control on, so this — its absence — is
    /// the news, and the one definition the row's mark and the reading
    /// pane's `answer` line both read.
    public var lacksRemoteControl: Bool {
        guard session.kind == .background, let job else { return false }
        return (session.state == .working || session.state == .blocked) && !job.remoteControl
    }

    /// The folder in one word: the repository's own name (a worktree row
    /// names its repository, not the worktree), or `~`. The path differs
    /// from row to row only in this word — 8 of 13 rows shared the rest —
    /// and the whole of it is the tooltip's.
    public func folderName(shortCwd: (String) -> String = { $0 }) -> String {
        let path = shortCwd(worktree?.repo ?? session.cwd)
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    /// The row's second line: the harness's state and status, or — for a
    /// draft (v5), never prompted and waiting for you to start it — not the
    /// "blocked · idle" of a session with a question.
    public var stateText: String {
        if draft { return "draft · send a prompt to start" }
        var text = session.state?.rawValue ?? session.kind.rawValue
        if let status = session.status { text += " · \(status.rawValue)" }
        return text
    }
}

/// A time as a person reads it at a glance — lore's ladder, inherited so
/// the two apps say a moment the same way: `now`, `12m ago`, `17:45`,
/// `yest`, `2 sep`. The relative form lives one hour and no longer: past
/// that "3h ago" makes the reader do the subtraction the clock already
/// did. 24-hour, never raw ISO; the full stamp is the tooltip's.
public enum Stamp {
    public static func text(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if calendar.isDate(date, inSameDayAs: now) {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yest"
        }
        let parts = calendar.dateComponents([.day, .month], from: date)
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let month = months[max(0, min(11, (parts.month ?? 1) - 1))]
        return "\(parts.day ?? 0) \(month)"
    }
}

extension WorktreeInfo {
    /// The branch without the harness's `worktree-`, which is the name
    /// its folder has. The prefix led 8 of 9 branches on the roster and
    /// was the part a narrow row kept: `wor…t-4204`.
    public var shortBranch: String {
        let prefix = "worktree-"
        return branch.hasPrefix(prefix) && branch.count > prefix.count ? String(branch.dropFirst(prefix.count)) : branch
    }

    /// "3 ahead, 1 unpushed", "3 ahead, 2 behind (master moved)", "level
    /// with master; master has 2 unpushed" — the submenu's last line and
    /// the row's tooltip.
    public var standing: String {
        var parts: [String] = []
        if ahead == 0 && behind == 0 {
            parts.append("level with \(base)")
        } else {
            if ahead > 0 { parts.append("\(ahead) ahead") }
            if behind > 0 { parts.append("\(behind) behind (\(base) moved)") }
            if ahead == 0 { parts.append("nothing to merge") }
        }
        if let up = unpushed, up > 0 { parts.append("\(up) unpushed") }
        if let down = unpulled, down > 0 { parts.append("\(down) unpulled") }
        var text = parts.joined(separator: ", ")
        var theirs: [String] = []
        if let up = baseUnpushed, up > 0 { theirs.append("\(up) unpushed") }
        if let down = baseUnpulled, down > 0 { theirs.append("\(down) unpulled") }
        if !theirs.isEmpty { text += "; \(base) has " + theirs.joined(separator: ", ") }
        return text
    }
}

extension Session {
    /// Interactive rows have no short id and cannot be attached (experiment 1).
    public var isAttachable: Bool { kind == .background }
}
