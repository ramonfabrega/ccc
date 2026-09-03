import AppKit
import CCCKit
import SwiftUI

/// One window: roster on the left, the pane on the right, a banner above
/// when the roster changed shape or the socket is held elsewhere. Every
/// button calls the same `PaneController` method the socket does.
@MainActor
final class MainWindowController: NSWindowController {
    let controller: PaneController
    private let split = NSSplitView()
    private let paneContainer = NSView()
    private let placeholder = NSTextField(labelWithString: "Select a session and press ⏎ to attach")
    private let banner = NSTextField(wrappingLabelWithString: "")
    private let bannerBox = NSView()
    private var bannerTask: Task<Void, Never>?
    private var noticeText: String?
    private var noticeTask: Task<Void, Never>?

    init(controller: PaneController) {
        self.controller = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = BuildInfo.current.appTitle
        window.titlebarAppearsTransparent = true
        window.setFrameAutosaveName("ccc.main")
        window.minSize = NSSize(width: 800, height: 400)
        // ⌘W closes the window, not the app; the controller keeps it so the
        // menubar item, the Dock, ⌘0 and `ccc window show` bring it back.
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
        controller.makeHost = { [weak self] cols, rows in
            let bounds = self?.paneContainer.bounds ?? CGRect(x: 0, y: 0, width: 8 * cols, height: 17 * rows)
            return PaneController.makeDefaultHost(frame: bounds)
        }
        controller.onSessionStarted = { [weak self] session in self?.mount(session) }
        controller.onSessionEnded = { [weak self] _ in self?.unmount() }
        controller.defaultSize = gridSize()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: layout

    private func build() {
        guard let content = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])

        bannerBox.wantsLayer = true
        bannerBox.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.25).cgColor
        banner.font = .systemFont(ofSize: 12)
        banner.translatesAutoresizingMaskIntoConstraints = false
        bannerBox.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: bannerBox.topAnchor, constant: 6),
            banner.bottomAnchor.constraint(equalTo: bannerBox.bottomAnchor, constant: -6),
            banner.leadingAnchor.constraint(equalTo: bannerBox.leadingAnchor, constant: 12),
            banner.trailingAnchor.constraint(equalTo: bannerBox.trailingAnchor, constant: -12),
        ])
        bannerBox.isHidden = true
        // A click dismisses a notice; the host and shape lines are
        // conditions and stay until they clear themselves.
        bannerBox.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(bannerClicked(_:))))
        bannerBox.toolTip = "Click to dismiss"
        root.addArrangedSubview(bannerBox)
        bannerBox.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        split.isVertical = true
        split.dividerStyle = .thin
        let roster = NSHostingView(rootView: RosterView(poller: controller.poller, hosts: controller.hosts, attach: { [weak self] ref in
            self?.attach(ref)
        }, detach: { [weak self] in
            self?.detachAction(nil)
        }, attachCommandLine: { [weak self] ref in
            self?.controller.attachCommandLine(for: ref) ?? "claude attach \(ref.id)"
        }, mark: { [weak self] ref, change in
            self?.mark(ref, change)
        }, delete: { [weak self] ref in
            self?.confirmDelete(ref)
        }, newSession: { [weak self] in
            self?.newSessionAction(nil)
        }, fork: { [weak self] ref in
            self?.presentNewSession(from: ref)
        }))
        // No intrinsic size from SwiftUI: the split view and the window
        // decide the roster's size, not the other way around.
        roster.sizingOptions = []
        roster.setContentHuggingPriority(.defaultLow, for: .horizontal)
        roster.setContentHuggingPriority(.defaultLow, for: .vertical)
        split.addArrangedSubview(roster)
        split.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        split.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        root.distribution = .fill

        paneContainer.wantsLayer = true
        paneContainer.layer?.backgroundColor = NSColor.black.cgColor
        placeholder.textColor = .secondaryLabelColor
        placeholder.alignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        paneContainer.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: paneContainer.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: paneContainer.centerYAnchor),
        ])
        split.addArrangedSubview(paneContainer)
        root.addArrangedSubview(split)
        split.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        roster.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        paneContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        DispatchQueue.main.async { [split] in split.setPosition(420, ofDividerAt: 0) }

        bannerTask = Task { @MainActor [weak self] in
            while let self {
                self.refreshBanner()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshBanner() {
        var parts: [String] = []
        if let noticeText { parts.append(noticeText) }
        let state = controller.poller.state
        // Per host, never roster-wide: studio asleep is one line about
        // studio, above a roster that still shows this Mac's sessions and
        // studio's last known ones (marked stale in the footer).
        for failed in state.failures {
            let kept = failed.rows.isEmpty ? "" : " — showing its \(failed.rows.count) sessions from \(Self.age(since: failed.lastSuccessAt))"
            parts.append("\(failed.host): \(failed.error ?? "unreachable")\(kept)")
        }
        parts += state.notes
        if !state.issues.isEmpty {
            parts.append("roster shape changed — showing what still decodes: " +
                         state.issues.prefix(3).map(\.description).joined(separator: "; ") +
                         (state.issues.count > 3 ? " (+\(state.issues.count - 3))" : ""))
        }
        let text = parts.joined(separator: "\n")
        if banner.stringValue != text { banner.stringValue = text }
        bannerBox.isHidden = text.isEmpty
    }

    /// A sentence on the banner. Transient by default: it goes away on
    /// its own, or on a click, because "installed …" and "archived a1b2"
    /// are answers, not conditions. Found on air 2026-09-02 when the
    /// first notice a hand ever triggered ("Install ‘ccc’ Command…")
    /// stayed up for good — before this, nothing ever cleared it.
    /// `for: nil` keeps one up until the next notice or a click: the
    /// socket held by another process is a condition worth staring at.
    func showNotice(_ text: String, for duration: Duration? = .seconds(8)) {
        noticeText = text
        noticeTask?.cancel()
        noticeTask = nil
        refreshBanner()
        guard let duration else { return }
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.noticeText == text else { return }
            self.noticeText = nil
            self.refreshBanner()
        }
    }

    @objc private func bannerClicked(_ sender: Any?) {
        guard noticeText != nil else { return }
        noticeText = nil
        noticeTask?.cancel()
        noticeTask = nil
        refreshBanner()
    }

    // MARK: pane

    /// Cells that fit the pane at SwiftTerm's default font.
    private func gridSize() -> (cols: Int, rows: Int) {
        let bounds = paneContainer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return (120, 40) }
        let cell = SwiftTermHost.estimatedCellSize()
        return (max(20, Int(bounds.width / cell.width)), max(5, Int(bounds.height / cell.height)))
    }

    private func mount(_ session: AttachSession) {
        guard let view = session.host.view else { return }
        placeholder.isHidden = true
        view.frame = paneContainer.bounds
        view.autoresizingMask = [.width, .height]
        paneContainer.addSubview(view)
        window?.makeFirstResponder(view)
        if let host = session.host as? SwiftTermHost {
            host.onSizeChanged = { [weak session] cols, rows in session?.viewResized(cols: cols, rows: rows) }
            // The view just took the container's frame; make sure the child
            // hears the size it actually got, not the pre-mount estimate.
            let dims = host.size
            session.viewResized(cols: dims.cols, rows: dims.rows)
        } else if let pane = session.host as? GhosttyPane {
            pane.onSizeChanged = { [weak session] cols, rows in session?.viewResized(cols: cols, rows: rows) }
            let dims = pane.size
            pane.resize(cols: dims.cols, rows: dims.rows)
            session.viewResized(cols: dims.cols, rows: dims.rows)
        }
        window?.title = "\(BuildInfo.current.appTitle) — \(session.ref)"
    }

    private func unmount() {
        for view in paneContainer.subviews where view !== placeholder { view.removeFromSuperview() }
        placeholder.isHidden = false
        window?.title = BuildInfo.current.appTitle
    }

    func attach(_ ref: SessionRef) {
        controller.defaultSize = gridSize()
        do {
            try controller.attach(ref: ref)
        } catch {
            showNotice("\(error)")
        }
    }

    @objc func detachAction(_ sender: Any?) {
        Task { await controller.detach() }
    }

    // MARK: new session (v5)

    private var newSessionSheet: NSWindow?

    /// ⌘N, the Session menu, the roster header's +: one sheet, whose
    /// Start runs what `ccc spawn` runs and then attaches (unless told
    /// not to). The sheet stays up over a harness error with the fields
    /// intact.
    @objc func newSessionAction(_ sender: Any?) {
        presentNewSession(from: nil)
    }

    /// ⇧⌘N (slice 3): the sheet with its From row set to the attached
    /// session — or, with nothing attached, open for the row to be picked.
    /// The row's context menu and `f` name the row directly.
    @objc func forkSessionAction(_ sender: Any?) {
        presentNewSession(from: controller.poller.attachedRef)
    }

    private func presentNewSession(from source: SessionRef?) {
        guard let window, newSessionSheet == nil else { return }
        let model = NewSessionModel(
            hosts: controller.hosts.hosts,
            recentFolders: { [weak self] host in self?.recentFolders(on: host) ?? [] },
            sources: { [weak self] host in self?.spawnSources(on: host) ?? [] },
            shortCwd: { [weak self] cwd, host in self?.controller.hosts.shortCwd(cwd, host: host) ?? cwd },
            commandLine: { [weak self] host, request in
                guard let self, let cli = try? self.controller.cli(for: SessionRef(host: host, id: "-")) else { return "" }
                return cli.spawnCommandLine(request)
            },
            from: source)
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: NewSessionView(
            model: model,
            submit: { [weak self] in self?.submitNewSession(model) },
            cancel: { [weak self] in self?.dismissNewSession() })))
        newSessionSheet = sheet
        window.beginSheet(sheet)
    }

    private func dismissNewSession() {
        guard let window, let sheet = newSessionSheet else { return }
        window.endSheet(sheet)
        newSessionSheet = nil
    }

    private func submitNewSession(_ model: NewSessionModel) {
        guard !model.busy else { return }
        model.busy = true
        model.error = nil
        Task { @MainActor in
            defer { model.busy = false }
            do {
                let result = try await controller.spawn(model.request, on: model.host)
                model.remember()
                dismissNewSession()
                showNotice(result.description)
                if model.attachAfter {
                    // One pane: a fork is usually made from the session on
                    // screen (⇧⌘N), and attach refuses while one is attached
                    // — so leave it first. `detach()` returns once the child
                    // has exited, which is what attach checks.
                    await controller.detach()
                    attach(result.ref)
                }
            } catch {
                model.error = "\(error)"
            }
        }
    }

    /// Distinct folders the roster knows on a host, most recent first,
    /// a worktree folded to its repository. Where new work usually starts.
    private func recentFolders(on host: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for row in controller.poller.state.sorted where row.host == host {
            let root = RepoPath.root(of: row.session.cwd)
            if seen.insert(root).inserted { out.append(root) }
            if out.count == 8 { break }
        }
        return out
    }

    /// What a fork can start from on a host (slice 3): every attachable
    /// row with a session id, in the roster's activity order, archived
    /// ones last — an old finished thread is a fine thing to continue.
    private func spawnSources(on host: String) -> [SpawnSource] {
        let rows = controller.poller.state.sorted.filter {
            $0.host == host && $0.session.isAttachable && !($0.session.sessionId ?? "").isEmpty
        }
        return (rows.filter { !$0.archived } + rows.filter(\.archived)).map { row in
            SpawnSource(ref: row.ref,
                        label: "\(row.session.name ?? row.session.id) · \(row.session.id)\(row.archived ? " (archived)" : "")",
                        sessionId: row.session.sessionId ?? "",
                        cwd: row.session.cwd)
        }
    }

    /// Archive / pin (v4): the controller does what `ccc archive <ref>`
    /// does, and the answer — ours, or the far side's — is the notice.
    func mark(_ ref: SessionRef, _ change: MarkChange) {
        Task { @MainActor in
            do {
                showNotice(try await controller.mark(ref, change))
            } catch {
                showNotice("\(error)")
            }
        }
    }

    /// The roster's Delete: one alert naming what goes, then the harness's
    /// `rm` behind the host prefix. Its guard is the safety net — a dirty
    /// worktree is "kept", and that sentence lands here as the notice.
    func confirmDelete(_ ref: SessionRef) {
        let row = controller.poller.state.rows.first { $0.ref == ref }
        let alert = NSAlert()
        alert.messageText = "Delete \(row?.session.name ?? ref.description)?"
        let cwd = row.map { controller.hosts.shortCwd($0.session.cwd, host: $0.host) } ?? ""
        alert.informativeText = "Runs `claude rm \(ref.id)`" + (ref.isLocal ? "" : " on \(ref.host)")
            + ": the session and its worktree go, unless the worktree has uncommitted or unpushed work, in which case the harness keeps both."
            + (cwd.isEmpty ? "" : "\n\n\(cwd)")
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { @MainActor in
            do {
                showNotice(try await controller.delete(ref))
            } catch {
                showNotice("\(error)")
            }
        }
    }

    @objc func showAction(_ sender: Any?) {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// The socket's window verbs; `close` is literally ⌘W, `resize W H`
    /// is the user dragging the corner (check 5's twin: the pane and the
    /// child must follow the new grid).
    func windowAction(_ action: String) -> Bool {
        let parts = action.split(separator: " ").map(String.init)
        switch parts.first {
        case "show": showAction(nil)
        case "hide": window?.orderOut(nil)
        case "close": window?.performClose(nil)
        case "resize":
            guard parts.count == 3, let w = Double(parts[1]), let h = Double(parts[2]), let window else { return false }
            var frame = window.frame
            frame.origin.y += frame.height - h
            frame.size = NSSize(width: w, height: h)
            window.setFrame(frame, display: true, animate: false)
        default: return false
        }
        return true
    }

    @objc func refreshAction(_ sender: Any?) {
        Task { await controller.poller.tick() }
    }

    /// "42 s ago", "3 min ago", or "a while ago" when there never was a
    /// success to date from.
    static func age(since date: Date?) -> String {
        guard let date else { return "before" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 90 { return "\(seconds) s ago" }
        if seconds < 5400 { return "\(seconds / 60) min ago" }
        return "\(seconds / 3600) h ago"
    }

    /// The whole window as PNG via our own view hierarchy — TCC-free eyes on
    /// our UI (scry's `peek --window`). Material backgrounds render black;
    /// layout and the pane composite correctly, which is what matters.
    func peek() -> Data? {
        guard let window, let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return nil }
        content.cacheDisplay(in: content.bounds, to: rep)
        // A Metal layer is invisible to cacheDisplay; composite the pane's
        // own offscreen render into its place so peek shows the v1 pane too.
        if let pane = controller.session?.host as? GhosttyPane, let view = pane.view, let image = pane.snapshotImage(),
           let context = NSGraphicsContext(bitmapImageRep: rep) {
            let frameInContent = view.convert(view.bounds, to: content)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            // cacheDisplay draws in the content view's coordinate space (flipped or not);
            // NSBitmapImageRep contexts are bottom-left, so flip y for a non-flipped content view.
            let y = content.isFlipped ? content.bounds.height - frameInContent.maxY : frameInContent.minY
            context.cgContext.draw(image, in: CGRect(x: frameInContent.minX, y: y, width: frameInContent.width, height: frameInContent.height))
            NSGraphicsContext.restoreGraphicsState()
        }
        return rep.representation(using: .png, properties: [:])
    }
}
