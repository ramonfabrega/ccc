import CCCKit
import SwiftUI

/// The roster: what `claude agents` shows, plus the model column. Sorted
/// blocked → working → failed → done/stopped, newest first within a rank.
/// Enter or double-click attaches; the attached row is marked.
struct RosterView: View {
    let poller: RosterPoller
    let attach: (String) -> Void
    let detach: () -> Void
    @State private var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List(poller.state.sorted, id: \.session.id, selection: $selection) { row in
                RosterRow(row: row)
                    .tag(row.session.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { attach(row.session.id) }
                    .contextMenu {
                        Button("Attach") { attach(row.session.id) }.disabled(!row.session.isAttachable)
                        if row.attached { Button("Detach") { detach() } }
                        if let sid = row.session.sessionId {
                            Button("Copy session id") { NSPasteboard.general.setString(sid, forType: .string) }
                        }
                        Button("Copy `claude attach \(row.session.id)`") {
                            NSPasteboard.general.setString("claude attach \(row.session.id)", forType: .string)
                        }
                    }
            }
            .listStyle(.inset)
            .onKeyPress(.return) {
                guard let selection, let row = poller.state.rows.first(where: { $0.session.id == selection }),
                      row.session.isAttachable else { return .ignored }
                attach(selection)
                return .handled
            }
            footer
        }
        .frame(minWidth: 320)
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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
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
        .help("\(row.session.id) · \(row.session.cwd)")
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

    private var shortCwd: String {
        row.session.cwd.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private func shortModel(_ m: String) -> String { m.replacingOccurrences(of: "claude-", with: "") }
}

extension Session {
    /// Interactive rows have no short id and cannot be attached (experiment 1).
    var isAttachable: Bool { kind == .background }
}
