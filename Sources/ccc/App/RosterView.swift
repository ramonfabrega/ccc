import CCCKit
import SwiftUI

/// AppKit asking SwiftUI for the keyboard (v7 slice 1). The list's focus
/// is a `@FocusState` the view owns; the window cannot reach it, so it
/// bumps a counter the view observes and names the row to select.
@MainActor
final class RosterFocus: ObservableObject {
    @Published private(set) var requests = 0
    private(set) var target: SessionRef?

    func request(selecting ref: SessionRef?) {
        target = ref
        requests += 1
    }

    /// Select a row and leave the keyboard where it is: `ccc show <ref>
    /// --select`, which must not take the pane's keys from someone typing.
    @Published private(set) var selects = 0
    private(set) var selectTarget: SessionRef?

    func select(_ ref: SessionRef) {
        selectTarget = ref
        selects += 1
    }
}

/// How much of the window the roster has (2026-11-13). With a session in
/// the pane it is the sidebar it always was. With nothing attached there
/// is no pane, and the roster is the whole window: the same rows, the
/// same left `sidebarWidth` of each, and to the right of that the
/// sentence the sidebar cuts at sixty characters, in full.
///
/// The window owns this — only it knows whether a pane is on screen — and
/// the roster draws to it.
@MainActor
final class RosterLayout: ObservableObject {
    /// No pane: the roster fills the window.
    @Published var expanded = false
    /// The roster's width when a pane is beside it, which is also where a
    /// row's identity ends when it is not: an attach must not move it.
    @Published var sidebarWidth: CGFloat = 420
    /// The one condition about this window — another ccc holds the
    /// control socket. It was the pane's empty state while there was one.
    @Published var socketNote: String?
}

/// The roster: what `claude agents` shows, plus the model column and our
/// marks (v4). Grouped and sorted by the View menu's choices (`RosterGroup`,
/// `RosterSort`, persisted in UserDefaults — `ccc list --group/--sort` are
/// the twins); pinned rows first under every sort; archived rows folded
/// away behind the header's count unless they are asking for input. Enter
/// or double-click attaches; the attached row is marked.
struct RosterView: View {
    let poller: RosterPoller
    /// For shortening a row's cwd with the home of the host that answered
    /// it — `~/code` on studio is not `~/code` on air once the usernames
    /// differ.
    let hosts: HostConfig
    /// The window's request for the keyboard (v7 slice 1): ← on an empty
    /// prompt in the pane lands here, selecting the attached row.
    @ObservedObject var focus: RosterFocus
    /// Sidebar, or the whole window (`RosterLayout`).
    @ObservedObject var layout: RosterLayout
    let attach: (SessionRef) -> Void
    /// → on the list, or ⏎ on the attached row: the pane takes the
    /// keyboard back.
    let focusPane: () -> Void
    let detach: () -> Void
    /// The exact command the pane would run for a row — asked of the
    /// controller rather than rebuilt here, so the copied line and the
    /// attached child can never disagree about the ssh hop.
    let attachCommandLine: (SessionRef) -> String
    /// Archive / pin and their undoes: the same `MarkChange` that
    /// `ccc archive <ref>` takes.
    let mark: (SessionRef, MarkChange) -> Void
    /// The harness's `rm`, behind a confirmation the controller owns.
    let delete: (SessionRef) -> Void
    /// `ccc forget <ref>`: the same `rm`, refused when it would take a tree.
    let forget: (SessionRef) -> Void
    /// The New Session sheet (v5) — ⌘N's twin in the header.
    let newSession: () -> Void
    /// The same sheet on a row's host and folder (slice 3): `ccc spawn
    /// --host <h> --cwd <dir>` with the row's answers filled in.
    let newSessionHere: (SessionRef) -> Void
    /// The row's Merge submenu (v6): `ccc merge <ref> --<strategy>`.
    let merge: (SessionRef, MergeStrategy) -> Void
    /// The submenu's Push items (v6 slice 3): `ccc push <ref> [--base]`.
    let push: (SessionRef, PushTarget) -> Void
    /// The submenu's Update item (v6 slice 6): `ccc update <ref>`.
    let update: (SessionRef) -> Void
    /// The submenu's Fetch and Pull items (v6 slice 7): `ccc fetch|pull <ref>`.
    let fetch: (SessionRef) -> Void
    let pull: (SessionRef) -> Void
    /// Open in Terminal (v6 slice 4): `ccc shell <ref>`.
    let openShell: (SessionRef, _ atRepo: Bool) -> Void
    /// Open in lore: `ccc lore <ref>` — the job's page in lore's explorer.
    let openLore: (SessionRef) -> Void
    /// Whether the shell pane on screen is the one this row's item would
    /// open (v12 slice 1) — asked when the menu opens, so the item reads
    /// "Close Terminal" for the row the shell is actually in.
    let shellIsOpen: (SessionRef, _ atRepo: Bool) -> Bool
    /// That item's other half: `ccc shell --close`, ⇧⌘T's twin.
    let closeShell: () -> Void
    /// The window keeps the selection for ⌘T when nothing is attached.
    let selectionChanged: (SessionRef?) -> Void
    @State private var selection: SessionRef?
    /// Keyboard focus on the list, set by the same click that selects a
    /// row. Measured 2026-09-02 on the shipped build: a click highlighted
    /// the row and then ⏎, `a`, `p`, `n` all went nowhere, because the
    /// row's tap gesture takes the mouse before the table can become first
    /// responder. The click is what makes the roster the keyboard's
    /// target; a click in the pane hands it back.
    @FocusState private var focused: Bool
    @AppStorage(RosterPrefs.archivedKey) private var showsArchived = false
    @AppStorage(RosterPrefs.groupKey) private var groupName = RosterGroup.none.rawValue
    @AppStorage(RosterPrefs.sortKey) private var sortName = RosterSort.activity.rawValue

    private var group: RosterGroup { RosterGroup(rawValue: groupName) ?? .none }
    private var sort: RosterSort { RosterSort(rawValue: sortName) ?? .activity }

    private var sections: [RosterSection] {
        poller.state.sections(group: group, sort: sort, archived: showsArchived) { cwd, host in
            hosts.shortCwd(cwd, host: host)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List(selection: $selection) {
                // A host's condition sits above its rows: in its section's
                // header when grouped by host, at the top of the list
                // otherwise. The roster grows by a line; nothing outside
                // it moves, and the pane is never resized for it.
                let failures = poller.state.failures
                if group != .host, !failures.isEmpty {
                    Section {
                        ForEach(failures, id: \.host) { failed in HostCondition(poll: failed) }
                    }
                }
                ForEach(sections) { section in
                    Section {
                        ForEach(section.rows) { row in rowView(row) }
                    } header: {
                        // Only a header that has something to say: an empty
                        // one still takes a header's height at the top.
                        let failed = group == .host ? failures.first(where: { $0.host == section.title }) : nil
                        if !section.title.isEmpty || failed != nil {
                            VStack(alignment: .leading, spacing: 4) {
                                if !section.title.isEmpty { Text(section.title).font(.caption.monospaced()) }
                                if let failed { HostCondition(poll: failed) }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .focused($focused)
            .onKeyPress(.return) {
                guard let row = selectedRow, row.session.isAttachable else { return .ignored }
                attach(row.ref)
                return .handled
            }
            // The agents view's keys, plus ours: ⌫ deletes (confirmed),
            // `a` archives or unarchives, `p` pins or unpins, `n` starts a
            // new session in the row's folder.
            .onKeyPress(.delete) { press(delete) }
            .onKeyPress(.deleteForward) { press(delete) }
            .onKeyPress("a") { press { mark($0, marks($0)?.archived == true ? .unarchive : .archive) } }
            .onKeyPress("p") { press { mark($0, marks($0)?.pinned == true ? .unpin : .pin) } }
            .onKeyPress("n") { press(newSessionHere) }
            // `t` is the row item's key, so it toggles with it: the row
            // surface opens and closes, the menu bar keeps the two verbs
            // apart (⌘T opens or focuses, ⇧⌘T closes from anywhere).
            .onKeyPress("t") { press { shellIsOpen($0, false) ? closeShell() : openShell($0, false) } }
            .onKeyPress("l") { press(openLore) }
            .onKeyPress(.rightArrow) {
                focusPane()
                return .handled
            }
            .onChange(of: selection) { _, new in selectionChanged(new) }
            .onChange(of: focus.requests) { _, _ in
                if let target = focus.target { selection = target }
                focused = true
            }
            .onChange(of: focus.selects) { _, _ in
                if let target = focus.selectTarget { selection = target }
            }
            // With nothing attached the roster is the whole window and
            // the keyboard has nowhere else to be, so a row is always
            // selected: the one just left, else the top one, which
            // under the activity sort is whoever is waiting on you — and
            // takes the keyboard, since no pane is there to want it: ↑↓
            // read down the roster and ⏎ attaches, with no click first.
            .onChange(of: rowRefs, initial: true) { _, _ in keepSelection() }
            .onChange(of: poller.attachedRef) { old, new in
                if let new {
                    // The roster follows the pane: a `ccc attach`, a banner's
                    // click and a link all move it, and the highlighted row
                    // is never some other session than the one on screen.
                    selection = new
                } else {
                    // The pane just left, and its view took the keyboard
                    // with it. A row the user had moved to stays theirs.
                    if selection == nil { selection = old }
                    keepSelection()
                    focused = true
                }
            }
            footer
        }
        .frame(minWidth: 320)
    }

    private func rowView(_ row: SessionRow) -> some View {
        // A worktree row shows its repository, not the worktree's path —
        // and the repository's name, not its path: the branch already
        // names the worktree, and `~/code/fun/` is the same on every row.
        // The full path stays in the tooltip.
        RosterRow(row: row, showsHost: showsHost && group != .host,
                  // Grouped by repository, the header has said it once.
                  folder: group == .repo ? nil : row.folderName { hosts.shortCwd($0, host: row.host) },
                  stale: poller.state.host(row.host)?.isStale ?? false,
                  // The row's identity keeps the width it has as a sidebar,
                  // less the list's own insets, so nothing in it moves when
                  // the pane arrives.
                  blockWidth: layout.expanded ? max(240, layout.sidebarWidth - Self.rowInsets) : nil)
            .tag(row.ref)
            .contentShape(Rectangle())
            // Simultaneous, never exclusive: a plain `onTapGesture(count: 2)`
            // on a List row claims the first click while it waits for a
            // second, and the table's own selection then lands late or not
            // at all — the "iffy to click" of 2026-09-02. The single tap
            // selects outright, so a click on the dot or the gutter is a
            // click on the row, and the double tap rides beside it.
            .simultaneousGesture(TapGesture(count: 1).onEnded { selection = row.ref; focused = true })
            .simultaneousGesture(TapGesture(count: 2).onEnded { attach(row.ref) })
            .contextMenu { menu(for: row) }
    }

    /// What an inset list keeps on either side of a row, in total —
    /// measured off a 420 pt roster, whose row content is 388 pt wide.
    static let rowInsets: CGFloat = 32

    private var rowRefs: [SessionRef] { sections.flatMap { $0.rows.map(\.ref) } }

    private func keepSelection() {
        guard poller.attachedRef == nil else { return }
        let refs = rowRefs
        if let selection, refs.contains(selection) {
            // Already on a row; the keyboard is only claimed when the
            // selection is being made for the user.
            return
        }
        guard let first = refs.first else { return }
        selection = first
        focused = true
    }

    private var selectedRow: SessionRow? {
        guard let selection else { return nil }
        return poller.state.rows.first { $0.ref == selection }
    }

    private func marks(_ ref: SessionRef) -> SessionRow? { poller.state.rows.first { $0.ref == ref } }

    private func press(_ gesture: (SessionRef) -> Void) -> KeyPress.Result {
        guard let row = selectedRow, row.session.isAttachable else { return .ignored }
        gesture(row.ref)
        return .handled
    }

    /// Marks live with the session's host: a remote row read through the
    /// harness fallback has no ccc there to keep one.
    private func canMark(_ row: SessionRow) -> Bool {
        row.host == Host.localName || hosts.host(named: row.host)?.ccc != nil
    }

    /// One of the row's two terminal items, in whichever direction it is
    /// pointing. At most one item on the whole roster ever says "Close
    /// Terminal": there is one shell pane, in one folder.
    ///
    /// The repository item defers to the plain one when both name the same
    /// folder — a session opened *in* its main checkout, where `cwd` and
    /// `repo` are the same path — so the close is offered once.
    @ViewBuilder private func terminalItem(_ row: SessionRow, atRepo: Bool) -> some View {
        let suffix = atRepo ? " at Repository" : ""
        if shellIsOpen(row.ref, atRepo), !(atRepo && shellIsOpen(row.ref, false)) {
            Button("Close Terminal") { closeShell() }
        } else {
            Button("Open in Terminal\(suffix)") { openShell(row.ref, atRepo) }
        }
    }

    @ViewBuilder private func menu(for row: SessionRow) -> some View {
        Button("Attach") { attach(row.ref) }.disabled(!row.session.isAttachable)
        if row.attached { Button("Detach") { detach() } }
        Button("New Session Here…") { newSessionHere(row.ref) }
        // The shell pane's item is a toggle, not a one-way door (v7 slice
        // 3): the surface that opened it is the surface that closes it.
        // ⇧⌘T stays the global close — the one that reaches a shell whose
        // row is not on screen, and the only one that works from inside
        // the shell — but a row menu that only ever said "Open in Terminal"
        // left the pane looking like it had no way out.
        terminalItem(row, atRepo: false)
        if row.worktree != nil { terminalItem(row, atRepo: true) }
        // Beside the terminal: lore renders the job across its /clears and
        // respawns (history, cost, threads), which ccc does not.
        Button("Open in lore") { openLore(row.ref) }
        // The worktree's landing (v6): three strategies, each enabled by
        // what the row measures — fast-forward only while master has not
        // moved, merge and squash whenever there is work — and the
        // standing itself as the last, inert line. The merge runs where
        // the repository is, so a remote row needs a ccc there.
        if let wt = row.worktree {
            Menu("Merge \(wt.branch) into \(wt.base)") {
                Button("Fast-forward") { merge(row.ref, .ffOnly) }.disabled(!wt.canFastForward)
                Button("Merge (merge commit)") { merge(row.ref, .noFF) }.disabled(!wt.hasWork)
                Button("Squash into one commit") { merge(row.ref, .squash) }.disabled(!wt.hasWork)
                // Update from master (slice 6), GitHub's "Update branch":
                // the other direction, live while master holds commits
                // the branch lacks — the ↓ that disables Fast-forward.
                Divider()
                Button("Update from \(wt.base)" + (wt.behind > 0 ? " ↓\(wt.behind)" : "")) { update(row.ref) }
                    .disabled(!wt.canUpdate)
                // Push (slice 3), the step between landing and `claude rm`:
                // each item carries its own ⇡ count and is live only while
                // there is something to send. Never forced.
                if wt.unpushed != nil {
                    Divider()
                    Button("Push \(wt.branch)" + ((wt.unpushed ?? 0) > 0 ? " ⇡\(wt.unpushed!)" : "")) { push(row.ref, .branch) }
                        .disabled((wt.unpushed ?? 0) == 0)
                    Button("Push \(wt.base)" + ((wt.baseUnpushed ?? 0) > 0 ? " ⇡\(wt.baseUnpushed!)" : "")) { push(row.ref, .base) }
                        .disabled((wt.baseUnpushed ?? 0) == 0)
                    // Fetch and Pull master (slice 7): the other direction.
                    // Fetch is the one network call and is always on offer;
                    // Pull is fast-forward only and live while origin/master
                    // holds commits master lacks, as of the last fetch.
                    Divider()
                    Button("Fetch origin") { fetch(row.ref) }
                    Button("Pull \(wt.base)" + ((wt.baseUnpulled ?? 0) > 0 ? " ⇣\(wt.baseUnpulled!)" : "")) { pull(row.ref) }
                        .disabled(!wt.canPull)
                }
                Divider()
                Text(standing(wt))
            }
            .disabled(!canMark(row))
        }
        Divider()
        Button(row.pinned ? "Unpin" : "Pin") { mark(row.ref, row.pinned ? .unpin : .pin) }
            .disabled(!row.session.isAttachable || !canMark(row))
        Button(row.archived ? "Unarchive" : "Archive") { mark(row.ref, row.archived ? .unarchive : .archive) }
            .disabled(!row.session.isAttachable || !canMark(row))
        Divider()
        if let sid = row.session.sessionId {
            Button("Copy session id") { NSPasteboard.general.setString(sid, forType: .string) }
        }
        Button("Copy attach command") {
            NSPasteboard.general.setString(attachCommandLine(row.ref), forType: .string)
        }
        Divider()
        // Per host, not per row (v3, slice 2): the same mark the View menu
        // and `ccc hosts mute <name>` set. Read from the file when the menu
        // opens, so a shell's `ccc hosts mute` is reflected here.
        let muted = HostConfig.load().config.isMuted(row.host)
        let where_ = row.host == Host.localName ? "this Mac" : row.host
        Button(muted ? "Unmute notifications from \(where_)" : "Mute notifications from \(where_)") {
            try? AppDelegate.setMuted(row.host, !muted)
        }
        Divider()
        // Offered only on a row with no process: the guard's first test,
        // read off the row. The rest (a tree that would go) needs the job
        // file and git, and lands as the notice when the click is refused.
        Button("Forget…") { forget(row.ref) }
            .disabled(!row.session.isAttachable || row.session.pid != nil || row.session.status != nil
                      || ![.done, .stopped, .failed].contains(row.session.state))
        Button("Delete…") { delete(row.ref) }.disabled(!row.session.isAttachable)
    }

    private func standing(_ wt: WorktreeInfo) -> String { wt.standing }
}

extension RosterView {
    /// One Mac looks exactly like v1: the host is only worth a column once
    /// there is more than one answer to "which".
    private var showsHost: Bool {
        poller.state.rows.contains { $0.host != Host.localName }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Sessions").font(.headline)
            Button(action: newSession) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("New session (⌘N)")
            Spacer()
            let blocked = poller.state.rows.filter(\.isWaiting).count
            if blocked > 0 {
                Label("\(blocked) waiting", systemImage: "hand.raised.fill").foregroundStyle(.orange).font(.caption)
            }
            // The fold: how many rows are archived away, and the toggle
            // that shows them. Absent when there is nothing folded.
            let hidden = poller.state.hiddenCount
            if hidden > 0 || showsArchived {
                Button {
                    showsArchived.toggle()
                } label: {
                    Label("\(hidden) archived", systemImage: showsArchived ? "archivebox.fill" : "archivebox")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(showsArchived ? .primary : .secondary)
                .help(showsArchived ? "Hide archived sessions" : "Show archived sessions")
            }
            // Group and sort, the View menu's twin in the roster itself.
            Menu {
                Picker("Group By", selection: $groupName) {
                    ForEach(RosterGroup.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Sort By", selection: $sortName) {
                    ForEach(RosterSort.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
            } label: {
                Image(systemName: group == .none && sort == .activity ? "line.3.horizontal.decrease.circle"
                                                                        : "line.3.horizontal.decrease.circle.fill")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Group and sort")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private static let keys: [(String, String)] = [
        ("⏎", "attach"), ("t", "terminal"), ("l", "lore"), ("n", "new here"),
        ("a", "archive"), ("p", "pin"), ("⌫", "delete"),
    ]

    private var footer: some View {
        HStack(spacing: 8) {
            if let ms = poller.state.lastPollMs {
                Text(String(format: "poll %.0f ms", ms))
            }
            Text("\(poller.state.rows.count) sessions")
            ForEach(poller.state.failures, id: \.host) { failed in
                // "stale" when its last rows are still on screen, "down"
                // when it never answered; the line above its rows has the
                // sentence.
                Text("\(failed.host) \(failed.rows.isEmpty ? "down" : "stale")").foregroundStyle(.orange)
            }
            // The roster's own conditions, a word each with the detail as
            // the tooltip: fields that did not decode, and a marks file
            // that did not parse (marks ignored until it does).
            let issues = poller.state.issues
            if !issues.isEmpty {
                Text("shape changed").foregroundStyle(.orange)
                    .help("roster shape changed — showing what still decodes: " + issues.map(\.description).joined(separator: "; "))
            }
            let notes = poller.state.notes
            if !notes.isEmpty {
                Text("marks off").foregroundStyle(.orange).help(notes.joined(separator: "\n"))
            }
            if let note = layout.socketNote {
                Text("socket held").foregroundStyle(.orange)
                    .help("Another ccc holds the control socket — the command line talks to it; this window still attaches. (\(note))")
            }
            Spacer()
            // The roster's keys, written down only where there is room:
            // they were in the context menu and the source, and nowhere
            // on screen.
            if layout.expanded {
                HStack(spacing: 14) {
                    ForEach(Self.keys, id: \.0) { key, verb in
                        HStack(spacing: 5) {
                            Text(key).foregroundStyle(.primary)
                            Text(verb)
                        }
                    }
                }
                .font(.caption2.monospaced())
                .lineLimit(1)
                Spacer()
            }
            if let at = poller.state.lastPolledAt {
                Text(at, style: .time)
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 4)
    }
}

/// One host that is not answering, above its rows: what is wrong, in a
/// word, and when it last was right. The error itself is the tooltip.
struct HostCondition: View {
    let poll: HostPoll

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
            Text(poll.host).font(.caption.monospaced())
            Text(poll.rows.isEmpty ? "is down" : "is not answering").font(.caption)
            Spacer()
            Text(poll.rows.isEmpty ? "never answered" : "last seen \(Age.text(since: poll.lastSuccessAt))")
                .font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .help(poll.error ?? "")
        .listRowSeparator(.hidden)
    }
}

enum Age {
    /// "42 s ago", "3 min ago", "2 h ago"; "before" when there never was a
    /// success to date from.
    static func text(since date: Date?) -> String {
        guard let date else { return "before" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 90 { return "\(seconds) s ago" }
        if seconds < 5400 { return "\(seconds / 60) min ago" }
        return "\(seconds / 3600) h ago"
    }
}

struct RosterRow: View {
    let row: SessionRow
    var showsHost: Bool = false
    /// The folder as the row prints it — the repository's own name, not
    /// its path — or nil when the section header already says it.
    var folder: String?
    /// The host stopped answering; this row is its last known state.
    var stale: Bool = false
    /// Set when the roster is the whole window: the width the row's
    /// identity keeps — what it has as a sidebar — with the sentence
    /// moved out of line three into the room beside it. Nil in a sidebar.
    var blockWidth: CGFloat?

    /// The row's sentence, unless line two already carries it: the
    /// roster's own `waitingFor` is rendered up there, and saying the same
    /// thing twice is worse than saying it once.
    private var say: String? {
        guard let say = row.say else { return nil }
        return say == row.session.waitingFor ? nil : say
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            block.frame(width: blockWidth, alignment: .leading)
            if blockWidth != nil {
                // Beside the row, not under it — and laid over a spacer
                // rather than in the stack, so the row is exactly as tall
                // as its sidebar self and no row below it moves when the
                // pane arrives and this goes back to line three.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) { wideSentence }
                    .clipped()
            }
        }
        .padding(.vertical, 2)
        .opacity(stale ? 0.6 : (row.archived ? 0.7 : 1))
        .help("\(row.ref) · \(row.stateText) · \(row.session.cwd)\(stale ? " · stale: \(row.host) is not answering" : "")")
    }

    /// The sentence with room: three lines of it where the sidebar has
    /// one, and under a question the reply the daemon suggests — read from
    /// the job file since v10 and drawn nowhere until 2026-11-13.
    @ViewBuilder private var wideSentence: some View {
        let reply = row.isWaiting ? row.job?.suggestedReply : nil
        VStack(alignment: .leading, spacing: 2) {
            if let said = say ?? (row.isWaiting ? row.session.waitingFor : nil), !said.isEmpty {
                Text(said)
                    .font(.system(size: 12))
                    .foregroundStyle(row.isWaiting ? Color.orange : Color.primary.opacity(0.82))
                    .lineLimit(reply == nil ? 3 : 2)
                    .truncationMode(.tail)
                    .help(said)
            }
            if let reply {
                Text("↳ \(reply)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                    .help("The reply the daemon suggests: \(reply)")
            }
        }
        .frame(maxWidth: 780, alignment: .leading)
        .padding(.leading, 28)
        .padding(.trailing, 8)
    }

    /// The row as the sidebar has it: dot, name and model, line two, and
    /// the sentence on line three — or, when the sentence is beside the
    /// row, that line's height and nothing in it.
    private var block: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 2)
                .opacity(stale ? 0.35 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if showsHost {
                        Text(row.host)
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.secondary)
                    }
                    if row.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary) }
                    Text(row.session.name ?? row.session.id).fontWeight(row.attached ? .semibold : .regular).lineLimit(1)
                    if row.attached { Image(systemName: "rectangle.connected.to.line.below").font(.caption2) }
                    Spacer()
                    Text(row.model.map(shortModel) ?? "").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                // Line two, at whatever width the roster is (2026-11-13).
                // It used to be one fixed arrangement that the ellipsis
                // then cut: at 370 pt the branch read `wor…t-4204` and the
                // folder `…fun/attrition`. Now it is the widest of three
                // arrangements that fits — the folder is the first thing
                // to go, then the branch's arrows — and each is short
                // enough that the ordinary width needs no ellipsis at all.
                ViewThatFits(in: .horizontal) {
                    meta(folder: true, arrows: true)
                    meta(folder: false, arrows: true)
                    meta(folder: false, arrows: false)
                }
                // What the session has to say for itself (v10 slice 2).
                // The row used to name everything about a session except
                // what it was doing: the field with the most in it,
                // `detail`, narrates a *working* session, and working is
                // the one state ccc never notifies on — so the banner
                // could never have carried it and the row is its only
                // home. Orange while blocked, matching `waitingFor` above,
                // so "your turn" and the question read as one thing.
                if let say, !say.isEmpty {
                    Text(say)
                        .font(.caption)
                        .foregroundStyle(row.isWaiting ? Color.orange : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(say)
                        // Beside the row instead: keep the line, hide the
                        // words, so the row's height does not change.
                        .opacity(blockWidth == nil ? 1 : 0)
                        .accessibilityHidden(blockWidth != nil)
                }
            }
        }
    }

    /// Line two in one arrangement. What is **not** here is the change:
    /// measured on the 13 rows of 2026-11-13, the state words repeated the
    /// dot on 13 of 13, `worktree-` led 8 of 9 branches and was what the
    /// ellipsis kept, 8 rows shared a folder path that differed only in
    /// its last word, and the phone icon was on 9 — the rule `ccc list
    /// --help` already states is that the row *without* Remote Control
    /// carries the news.
    @ViewBuilder private func meta(folder showsFolder: Bool, arrows: Bool) -> some View {
        HStack(spacing: 6) {
            // The state, only where the dot does not already say it: a
            // green dot is working and an orange one is asking, but grey
            // is done *and* stopped, and a draft has to say what it wants.
            if let word = row.stateWord {
                Text(word).font(.caption).foregroundStyle(color).fixedSize()
            }
            // Only when nothing better is going below it: the roster's
            // `waitingFor` is often the placeholder "input needed", and
            // printing that beside the actual question is a repeat.
            if let waiting = row.session.waitingFor, say == nil {
                Text(waiting).font(.caption).foregroundStyle(.orange).lineLimit(1)
            }
            if row.archived {
                Label("archived", systemImage: "archivebox").font(.caption).foregroundStyle(.tertiary).fixedSize()
            }
            // Remote Control (item 17), inverted: `ccc spawn` defaults it
            // on, so the mark is for the live session that can *only* be
            // answered at the Mac it runs on.
            if row.lacksRemoteControl {
                Image(systemName: "iphone.slash")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("No Remote Control: dispatched --no-rc, so this session can only be answered on \(row.host == Host.localName ? "this Mac" : row.host), not from the Claude app")
            }
            // Launched with a permission mode that asks: it will stop at
            // its first prompt. Drawn only when it is the payload, which
            // excludes `default` and no mode at all: a missing flag never
            // meant the harness default, and `respawnFlags` writes a typed
            // `auto` as `default` on haiku, so neither is evidence.
            if row.session.kind == .background, row.job?.asksForPermission == true {
                Image(systemName: "questionmark.bubble")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("Launched --permission-mode \(row.job?.permissionMode ?? "?"): permission prompts block it until answered here or in the Claude app; `ccc spawn` defaults to auto")
            }
            // The worktree (v6): the branch — by the name its folder has,
            // without the harness's `worktree-` — with what it holds over
            // its base and, in orange since it blocks a fast-forward, what
            // the base holds over it.
            if let wt = row.worktree {
                HStack(spacing: 3) {
                    Text("⎇ \(wt.shortBranch)").foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                    if arrows {
                        if wt.ahead > 0 { Text("↑\(wt.ahead)").foregroundStyle(.primary) }
                        if wt.behind > 0 { Text("↓\(wt.behind)").foregroundStyle(.orange) }
                        // ⇡ what origin does not have (slice 2): the
                        // harness keeps such a worktree on delete.
                        if let up = wt.unpushed, up > 0 { Text("⇡\(up)").foregroundStyle(.secondary) }
                        // ⇣ what origin has that this branch does not
                        // (slice 7): another Mac pushed to it.
                        if let down = wt.unpulled, down > 0 { Text("⇣\(down)").foregroundStyle(.secondary) }
                    }
                }
                .font(.caption.monospaced())
                .help("\(wt.branch) → \(wt.base): \(wt.standing)")
            }
            Spacer(minLength: 8)
            if showsFolder {
                HStack(spacing: 3) {
                    if let folder { Text(folder).foregroundStyle(.tertiary).lineLimit(1) }
                    // The base itself unpushed or behind: the other Mac
                    // cannot see what was just fast-forwarded here.
                    if let mark = row.worktree?.baseMark { Text(mark).foregroundStyle(.orange).help(row.worktree!.standing) }
                }
                .font(.caption.monospaced())
            }
        }
    }

    private var color: Color { Color(tone: row.tone) }

    private func shortModel(_ m: String) -> String { m.replacingOccurrences(of: "claude-", with: "") }
}

extension Color {
    /// The row's tone as a colour — one mapping for the roster's dot and
    /// state line.
    init(tone: SessionRow.Tone) {
        switch tone {
        case .draft: self = .indigo
        case .waiting: self = .orange
        case .busy: self = .green
        case .working: self = .mint
        case .failed: self = .red
        case .rested: self = .secondary
        case .gone: self = Color.secondary.opacity(0.5)
        case .live: self = .blue
        case .unknown: self = .secondary
        }
    }
}
