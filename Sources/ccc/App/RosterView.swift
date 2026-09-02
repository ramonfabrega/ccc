import CCCKit
import SwiftUI

/// The roster: what `claude agents` shows, plus the model column. Sorted
/// blocked → working → failed → done/stopped, newest first within a rank.
/// Enter or double-click attaches; the attached row is marked.
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
    @State private var selection: SessionRef?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List(poller.state.sorted, selection: $selection) { row in
                RosterRow(row: row, showsHost: showsHost, shortCwd: hosts.shortCwd(row.session.cwd, host: row.host),
                          stale: poller.state.host(row.host)?.isStale ?? false)
                    .tag(row.ref)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { attach(row.ref) }
                    .contextMenu {
                        Button("Attach") { attach(row.ref) }.disabled(!row.session.isAttachable)
                        if row.attached { Button("Detach") { detach() } }
                        if let sid = row.session.sessionId {
                            Button("Copy session id") { NSPasteboard.general.setString(sid, forType: .string) }
                        }
                        Button("Copy attach command") {
                            NSPasteboard.general.setString(attachCommandLine(row.ref), forType: .string)
                        }
                    }
            }
            .listStyle(.inset)
            .onKeyPress(.return) {
                guard let selection, let row = poller.state.rows.first(where: { $0.ref == selection }),
                      row.session.isAttachable else { return .ignored }
                attach(selection)
                return .handled
            }
            footer
        }
        .frame(minWidth: 320)
    }

    /// One Mac looks exactly like v1: the host is only worth a column once
    /// there is more than one answer to "which".
    private var showsHost: Bool {
        poller.state.rows.contains { $0.host != Host.localName }
    }

    private var header: some View {
        HStack {
            Text("Sessions").font(.headline)
            Spacer()
            let blocked = poller.state.rows.filter { $0.session.state == .blocked }.count
            if blocked > 0 {
                Label("\(blocked) waiting", systemImage: "hand.raised.fill").foregroundStyle(.orange).font(.caption)
            }
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
                    Spacer()
                    Text(shortCwd).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(stale ? 0.6 : 1)
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
