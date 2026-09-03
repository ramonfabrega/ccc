import AppKit
import CCCKit
import SwiftUI

/// The New Session sheet's state (v5). Every field is one of
/// `SpawnRequest`'s, so the sheet cannot ask for anything `ccc spawn`
/// cannot pass; the flags the sheet leaves out (permission mode, effort,
/// worktree, `--from`) are the command's alone until a hand wants them here.
@MainActor @Observable
final class NewSessionModel {
    var host: String
    var cwd: String
    var name = ""
    var model = ""
    var agent = ""
    var prompt = ""
    var attachAfter = true
    var busy = false
    var error: String?

    let hosts: [CCCKit.Host]
    /// Distinct folders the roster has seen on a host, most recent first,
    /// worktrees folded to their repository — the places a new session is
    /// most likely wanted.
    let recentFolders: (String) -> [String]
    let shortCwd: (String, String) -> String
    let commandLine: (String, SpawnRequest) -> String

    static let lastHostKey = "ccc.spawn.lastHost"
    static func lastCwdKey(_ host: String) -> String { "ccc.spawn.lastCwd.\(host)" }

    /// `here` is "New Session Here…" (a row's host and folder, slice 3):
    /// the sheet opens on that host in that folder instead of the
    /// remembered ones.
    init(hosts: [CCCKit.Host], recentFolders: @escaping (String) -> [String],
         shortCwd: @escaping (String, String) -> String,
         commandLine: @escaping (String, SpawnRequest) -> String,
         here: (host: String, cwd: String)? = nil) {
        self.hosts = hosts
        self.recentFolders = recentFolders
        self.shortCwd = shortCwd
        self.commandLine = commandLine
        let defaults = UserDefaults.standard
        let remembered = defaults.string(forKey: Self.lastHostKey)
        let host = here?.host ?? hosts.first { $0.name == remembered }?.name ?? hosts.first?.name ?? CCCKit.Host.localName
        self.host = host
        self.cwd = ""
        self.cwd = here?.cwd ?? defaultCwd(for: host)
    }

    func defaultCwd(for host: String) -> String {
        if let last = UserDefaults.standard.string(forKey: Self.lastCwdKey(host)), !last.isEmpty { return last }
        if let recent = recentFolders(host).first { return recent }
        return home(of: host)
    }

    func home(of host: String) -> String {
        guard let entry = hosts.first(where: { $0.name == host }) else { return "~" }
        if entry.isLocal { return FileManager.default.homeDirectoryForCurrentUser.path }
        return entry.home ?? "~"
    }

    var isLocal: Bool { hosts.first { $0.name == host }?.isLocal ?? true }
    var isDraft: Bool { request.isDraft }

    /// The words as they will run. A local cwd is this Mac's to expand.
    var request: SpawnRequest {
        var cwd = cwd.trimmingCharacters(in: .whitespaces)
        if isLocal, !cwd.isEmpty {
            cwd = (cwd as NSString).expandingTildeInPath
        }
        return SpawnRequest(cwd: cwd.isEmpty ? nil : cwd,
                            prompt: prompt,
                            name: name.trimmingCharacters(in: .whitespaces),
                            model: model.trimmingCharacters(in: .whitespaces),
                            agent: agent.trimmingCharacters(in: .whitespaces))
    }

    func remember() {
        let defaults = UserDefaults.standard
        defaults.set(host, forKey: Self.lastHostKey)
        defaults.set(cwd, forKey: Self.lastCwdKey(host))
    }
}

/// One sheet: where, what, and go. ⌘↩ submits, Esc cancels; an error
/// from the harness stays in the sheet with the fields intact, so a typo
/// costs a keystroke rather than the whole form.
struct NewSessionView: View {
    @Bindable var model: NewSessionModel
    let submit: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Session").font(.title3.weight(.semibold))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                if model.hosts.count > 1 {
                    GridRow {
                        Text("Host")
                        Picker("", selection: $model.host) {
                            ForEach(model.hosts) { host in Text(host.name).tag(host.name) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200, alignment: .leading)
                        .onChange(of: model.host) { _, host in model.cwd = model.defaultCwd(for: host) }
                    }
                }
                GridRow {
                    Text("Folder")
                    HStack(spacing: 6) {
                        TextField("", text: $model.cwd, prompt: Text(model.home(of: model.host)))
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                        let recent = model.recentFolders(model.host)
                        if !recent.isEmpty {
                            Menu {
                                ForEach(recent, id: \.self) { folder in
                                    Button(model.shortCwd(folder, model.host)) { model.cwd = folder }
                                }
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .help("Folders the roster has seen on \(model.host)")
                        }
                        if model.isLocal {
                            Button("Choose…") { choose() }
                        }
                    }
                }
                GridRow {
                    Text("Name")
                    TextField("", text: $model.name, prompt: Text("optional — the harness names it otherwise"))
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Model")
                    HStack(spacing: 6) {
                        TextField("", text: $model.model, prompt: Text("default"))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 160)
                        ForEach(["opus", "sonnet", "haiku"], id: \.self) { alias in
                            Button(alias) { model.model = alias }
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }
                }
                GridRow {
                    Text("Agent")
                    TextField("", text: $model.agent, prompt: Text("optional"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
                GridRow(alignment: .top) {
                    Text("Prompt").padding(.top, 4)
                    VStack(alignment: .leading, spacing: 4) {
                        TextEditor(text: $model.prompt)
                            .font(.body)
                            .frame(minHeight: 110)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
                        Text(model.isDraft
                             ? "Empty: the session starts and waits for its first prompt (a draft)."
                             : "The session starts working on this at once.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            // What will actually run — the same words `ccc spawn` prints,
            // so the sheet never promises a command it does not send.
            Text(model.commandLine(model.host, model.request))
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let error = model.error {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Toggle("Attach when started", isOn: $model.attachAfter)
                Spacer()
                if model.busy { ProgressView().controlSize(.small).padding(.trailing, 6) }
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(model.isDraft ? "Create Draft" : "Start", action: submit)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy)
            }
        }
        .padding(20)
        .frame(width: 620)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        let current = (model.cwd as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: current) { panel.directoryURL = URL(filePath: current) }
        if panel.runModal() == .OK, let url = panel.url { model.cwd = url.path }
    }
}
