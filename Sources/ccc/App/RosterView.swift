import CCCKit
import SwiftUI

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
    let attach: (SessionRef) -> Void
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
    @State private var selection: SessionRef?
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
                ForEach(sections) { section in
                    Section {
                        ForEach(section.rows) { row in rowView(row) }
                    } header: {
                        if !section.title.isEmpty { Text(section.title).font(.caption.monospaced()) }
                    }
                }
            }
            .listStyle(.inset)
            .onKeyPress(.return) {
                guard let row = selectedRow, row.session.isAttachable else { return .ignored }
                attach(row.ref)
                return .handled
            }
            // The agents view's keys, plus ours: ⌫ deletes (confirmed),
            // `a` archives or unarchives, `p` pins or unpins.
            .onKeyPress(.delete) { press(delete) }
            .onKeyPress(.deleteForward) { press(delete) }
            .onKeyPress("a") { press { mark($0, marks($0)?.archived == true ? .unarchive : .archive) } }
            .onKeyPress("p") { press { mark($0, marks($0)?.pinned == true ? .unpin : .pin) } }
            footer
        }
        .frame(minWidth: 320)
    }

    private func rowView(_ row: SessionRow) -> some View {
        RosterRow(row: row, showsHost: showsHost && group != .host,
                  shortCwd: hosts.shortCwd(row.session.cwd, host: row.host),
                  stale: poller.state.host(row.host)?.isStale ?? false)
            .tag(row.ref)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { attach(row.ref) }
            .contextMenu { menu(for: row) }
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

    @ViewBuilder private func menu(for row: SessionRow) -> some View {
        Button("Attach") { attach(row.ref) }.disabled(!row.session.isAttachable)
        if row.attached { Button("Detach") { detach() } }
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
        Button("Delete…") { delete(row.ref) }.disabled(!row.session.isAttachable)
    }

    /// One Mac looks exactly like v1: the host is only worth a column once
    /// there is more than one answer to "which".
    private var showsHost: Bool {
        poller.state.rows.contains { $0.host != Host.localName }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Sessions").font(.headline)
            Spacer()
            let blocked = poller.state.rows.filter { $0.session.state == .blocked }.count
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

    private var footer: some View {
        HStack(spacing: 8) {
            if let ms = poller.state.lastPollMs {
                Text(String(format: "poll %.0f ms", ms))
            }
            Text("\(poller.state.rows.count) sessions")
            ForEach(poller.state.failures, id: \.host) { failed in
                // "stale" when its last rows are still on screen, "down"
                // when it never answered; the banner has the sentence.
                Text("\(failed.host) \(failed.rows.isEmpty ? "down" : "stale")").foregroundStyle(.orange)
            }
            Spacer()
            if let at = poller.state.lastPolledAt {
                Text(at, style: .time)
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 4)
    }
}

struct RosterRow: View {
    let row: SessionRow
    var showsHost: Bool = false
    var shortCwd: String
    /// The host stopped answering; this row is its last known state.
    var stale: Bool = false

    var body: some View {
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
                HStack(spacing: 6) {
                    Text(stateText).font(.caption).foregroundStyle(color)
                    if let waiting = row.session.waitingFor {
                        Text(waiting).font(.caption).foregroundStyle(.orange)
                    }
                    if row.archived {
                        Label("archived", systemImage: "archivebox").font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(shortCwd).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(stale ? 0.6 : (row.archived ? 0.7 : 1))
        .help("\(row.ref) · \(row.session.cwd)\(stale ? " · stale: \(row.host) is not answering" : "")")
    }

    private var stateText: String {
        let s = row.session
        var text = s.state?.rawValue ?? s.kind.rawValue
        if let status = s.status { text += " · \(status.rawValue)" }
        return text
    }

    private var color: Color {
        switch row.session.state {
        case .blocked: return .orange
        case .working: return row.session.status == .busy ? .green : .mint
        case .failed: return .red
        case .done: return row.session.pid != nil ? .secondary : Color.secondary.opacity(0.5)
        case .stopped: return Color.secondary.opacity(0.5)
        case nil: return row.session.pid != nil ? .blue : .secondary
        }
    }

    private func shortModel(_ m: String) -> String { m.replacingOccurrences(of: "claude-", with: "") }
}

extension Session {
    /// Interactive rows have no short id and cannot be attached (experiment 1).
    var isAttachable: Bool { kind == .background }
}
