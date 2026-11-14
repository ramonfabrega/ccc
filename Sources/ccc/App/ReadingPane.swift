import CCCKit
import SwiftUI

/// What the reading pane is about: the roster's selection, and the one
/// condition about this window (another ccc holds the socket), which has
/// always been said in the pane's empty state.
@MainActor @Observable
final class ReadingPaneModel {
    var selection: SessionRef?
    var socketNote: String?
}

/// **The pane when nothing is attached** (2026-11-13): the selected row,
/// in full. It was one sentence on 860 points of black — "Select a session
/// and press ⏎ to attach" — beside a roster cutting every line it had to
/// fit 400. Now ↑↓ in the roster read down the fleet the way a mail client
/// reads down an inbox, and ⏎ opens the one worth opening. `ccc show` is
/// the twin and `SessionDetail` the one definition both draw.
///
/// The rules it is drawn to, most of them things the user has said about
/// other screens (relayed by lore, 2026-11-13):
///
/// - **The first thing on it is the thing to act on.** The question or
///   the result, in prose, at reading size. Everything else is quieter
///   and below.
/// - **Signal per pixel, not text per pixel.** A handful of facts, one
///   line each, never wrapped — the full value is the tooltip. Room for
///   everything is not a reason to draw everything.
/// - **Mono for names, labels and numbers; sans only for prose.**
/// - **Nothing shifts.** The header and the key legend hold their place
///   from row to row; only the prose between them changes length, and it
///   scrolls inside the pane rather than growing the page.
///
/// The theme's whatever the system appearance — on the terminal theme's own
/// ground (`MainWindowController.paneGround`): this is the terminal's
/// rectangle, and the session that mounts over it paints that colour. A
/// light reading pane — or a black one — would flash on every attach.
struct ReadingPane: View {
    let poller: RosterPoller
    let hosts: HostConfig
    let model: ReadingPaneModel

    private var row: SessionRow? {
        guard let ref = model.selection else { return nil }
        return poller.state.rows.first { $0.ref == ref }
    }

    private var showsHost: Bool { poller.state.rows.contains { $0.host != Host.localName } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let note = model.socketNote { socketNote(note) }
            if let row {
                let detail = SessionDetail(row: row, showsHost: showsHost) { hosts.shortCwd($0, host: row.host) }
                ScrollView {
                    content(detail)
                        .frame(maxWidth: Self.measure, alignment: .leading)
                        .padding(.horizontal, Self.margin)
                        .padding(.top, 36)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.automatic)
                if detail.attachable { legend }
            } else {
                Text("Select a session and press ⏎ to attach")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.quiet)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: MainWindowController.paneGround))
        .environment(\.colorScheme, Ink.scheme)
    }

    /// The prose column: wide enough for a path, narrow enough to read.
    private static let measure: CGFloat = 660
    private static let margin: CGFloat = 40

    @ViewBuilder private func content(_ detail: SessionDetail) -> some View {
        let tone = Color(tone: detail.tone)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(tone).frame(width: 9, height: 9)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(detail.name)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Ink.loud)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 16)
                if let model = detail.model {
                    Text(model).font(.system(size: 12, design: .monospaced)).foregroundStyle(Ink.quiet)
                }
            }
            Text(detail.state)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(tone)
                .padding(.leading, 19)
                .padding(.top, 5)

            ForEach(Array(detail.passages.enumerated()), id: \.offset) { _, passage in
                self.passage(passage, tone: tone)
            }

            Rectangle().fill(Ink.rule).frame(height: 1).padding(.top, 28).padding(.bottom, 16)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 7) {
                ForEach(Array(detail.facts.enumerated()), id: \.offset) { _, fact in
                    GridRow {
                        Text(fact.label).foregroundStyle(Ink.faint)
                        (Text(fact.value).foregroundStyle(Ink.body)
                            + Text(fact.note.map { "  \($0)" } ?? "").foregroundStyle(Ink.quiet))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(fact.full ?? ([fact.value, fact.note].compactMap { $0 }.joined(separator: " — ")))
                    }
                }
            }
            .font(.system(size: 12, design: .monospaced).monospacedDigit())
        }
    }

    @ViewBuilder private func passage(_ passage: SessionDetail.Passage, tone: Color) -> some View {
        let isReply = passage.kind == .reply
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // The label takes the row's colour only when it is the
                // call to act — the question. A result is not urgent.
                Text(passage.title.uppercased())
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(passage.kind == .say && passage.title == "asking" ? tone : Ink.faint)
                if isReply {
                    Button("copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(passage.text, forType: .string)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Ink.quiet)
                    .help("Copy the suggested reply")
                }
            }
            HStack(alignment: .top, spacing: 0) {
                if isReply {
                    Rectangle().fill(Ink.rule).frame(width: 2).padding(.trailing, 12)
                }
                Text(passage.text)
                    .font(.system(size: passage.kind == .say ? 15 : 13.5))
                    .lineSpacing(passage.kind == .say ? 5 : 4)
                    .foregroundStyle(passage.kind == .say ? Ink.loud : Ink.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, passage.kind == .say ? 26 : 20)
    }

    /// The roster's keys. They were only ever in the context menu and the
    /// source; this is the first place they are written down on screen.
    private var legend: some View {
        HStack(spacing: 18) {
            ForEach(Self.keys, id: \.0) { key, verb in
                HStack(spacing: 6) {
                    Text(key).foregroundStyle(Ink.body)
                    Text(verb).foregroundStyle(Ink.faint)
                }
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .lineLimit(1)
        .padding(.horizontal, Self.margin)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Ink.rule).frame(height: 1) }
    }

    private static let keys: [(String, String)] = [
        ("⏎", "attach"), ("t", "terminal"), ("l", "lore"), ("n", "new here"),
        ("a", "archive"), ("p", "pin"), ("⌫", "delete"),
    ]

    private func socketNote(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Another ccc holds the control socket — the command line talks to it; this window still attaches.")
            Text(note).foregroundStyle(Ink.quiet)
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.orange)
        .padding(.horizontal, Self.margin)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The reading pane's neutrals: the terminal theme's own foreground, in
/// steps. Not a palette of its own — a `CCC_THEME` with a light ground
/// would put pale text on it, and text here should sit in the same family
/// as the session that mounts over it. Colour proper is left to the row's
/// tone.
private enum Ink {
    private static let ink: Color = {
        let fg = Theme.active.foreground
        return Color(.sRGB, red: Double(fg.r) / 255, green: Double(fg.g) / 255, blue: Double(fg.b) / 255)
    }()
    static let loud = ink
    static let body = ink.opacity(0.80)
    static let quiet = ink.opacity(0.52)
    static let faint = ink.opacity(0.36)
    static let rule = ink.opacity(0.11)

    /// Which way the system controls inside the pane (the scroller) should
    /// lean: with the theme's ground, not the system appearance.
    static let scheme: ColorScheme = {
        let bg = Theme.active.background
        let luma = 0.2126 * Double(bg.r) + 0.7152 * Double(bg.g) + 0.0722 * Double(bg.b)
        return luma < 128 ? .dark : .light
    }()
}
