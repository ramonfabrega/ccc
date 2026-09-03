import AppKit
import CCCKit
import SwiftUI

/// One window: roster on the left, the pane on the right. Every button
/// calls the same `PaneController` method the socket does. What ccc has
/// to say goes to one of two places, by kind (2026-09-02): the answer to
/// a click floats over the pane (`NoticeHUD`); a condition — a host down,
/// the roster's shape changed — lives in the roster beside the rows it is
/// about, and the one condition about this window (another ccc holds the
/// socket) is the pane's empty state. Nothing ever resizes the pane for a
/// sentence: a pane resize is a PTY resize, and the TUI reflows.
@MainActor
final class MainWindowController: NSWindowController {
    let controller: PaneController
    private let split = NSSplitView()
    private let paneContainer = NSView()
    private let placeholder = NSTextField(wrappingLabelWithString: "")
    private let hud = NoticeHUD()
    /// The pane's empty state carries the one condition about this window.
    private var socketNote: String?

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

    /// Points between the pane's edges and the grid, the way every terminal
    /// leaves a gutter (Ghostty's `window-padding-x/y`): without it the
    /// first column touched the split divider and the cursor's left edge
    /// was the window's. The container paints the gutter black.
    private static let paneInset = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)

    private func build() {
        guard let window, let content = window.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        // The window is `.fullSizeContentView`, so `content` reaches under
        // the title bar. SwiftUI's roster knew — `NSHostingView` applies the
        // safe area on its own — while the AppKit banner and the pane did
        // not: the banner drew under the traffic lights and the terminal's
        // first row sat behind the title. The content layout guide is the
        // part of the window below the title bar; everything hangs from it.
        let below = (window.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? content.topAnchor
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: below),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])

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
        }, newSessionHere: { [weak self] ref in
            self?.presentNewSession(here: ref)
        }, merge: { [weak self] ref, strategy in
            self?.merge(ref, strategy)
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
        refreshPlaceholder()
        paneContainer.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: paneContainer.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: paneContainer.centerYAnchor),
            placeholder.widthAnchor.constraint(lessThanOrEqualTo: paneContainer.widthAnchor, multiplier: 0.7),
        ])
        hud.install(in: paneContainer)
        split.addArrangedSubview(paneContainer)
        root.addArrangedSubview(split)
        split.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        roster.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        paneContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        DispatchQueue.main.async { [split] in split.setPosition(420, ofDividerAt: 0) }
    }

    /// A sentence over the pane. An answer ("installed …", "archived a1b2")
    /// fades on its own; a problem stays until a click, because it is the
    /// guard talking. `for:` overrides the kind's own timing.
    func showNotice(_ text: String, kind: NoticeHUD.Kind = .answer, for duration: Duration?? = nil) {
        hud.show(text, kind: kind, for: duration ?? kind.duration)
    }

    /// Another ccc (or a headless attach) holds the control socket: the
    /// command line talks to it, this window still attaches. Said where it
    /// is true — the pane's empty state — for as long as it is.
    func noteSocketHeld(_ message: String) {
        socketNote = message
        refreshPlaceholder()
    }

    private func refreshPlaceholder() {
        var text = "Select a session and press ⏎ to attach"
        if let socketNote {
            text = "Another ccc holds the control socket — the command line talks to it; this window still attaches.\n(\(socketNote))\n\n" + text
        }
        placeholder.stringValue = text
    }

    // MARK: pane

    /// Cells that fit the pane at SwiftTerm's default font.
    private func gridSize() -> (cols: Int, rows: Int) {
        let bounds = Self.paneFrame(in: paneContainer.bounds)
        guard bounds.width > 0, bounds.height > 0 else { return (120, 40) }
        let cell = SwiftTermHost.estimatedCellSize()
        return (max(20, Int(bounds.width / cell.width)), max(5, Int(bounds.height / cell.height)))
    }

    private func mount(_ session: AttachSession) {
        guard let view = session.host.view else { return }
        placeholder.isHidden = true
        // Inset once; the autoresizing mask keeps the gutter as the window
        // resizes. The pane knows nothing of it — its view is its bounds —
        // so `peek`'s composite and the mouse's cell math stay right.
        view.frame = Self.paneFrame(in: paneContainer.bounds)
        view.autoresizingMask = [.width, .height]
        paneContainer.addSubview(view)
        hud.keepOnTop()
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

    private static func paneFrame(in bounds: NSRect) -> NSRect {
        let i = paneInset
        return NSRect(x: bounds.minX + i.left, y: bounds.minY + i.bottom,
                      width: max(0, bounds.width - i.left - i.right),
                      height: max(0, bounds.height - i.top - i.bottom))
    }

    private func unmount() {
        for view in paneContainer.subviews where view !== placeholder && view !== hud { view.removeFromSuperview() }
        placeholder.isHidden = false
        window?.title = BuildInfo.current.appTitle
    }

    func attach(_ ref: SessionRef) {
        controller.defaultSize = gridSize()
        do {
            try controller.attach(ref: ref)
        } catch {
            showNotice("\(error)", kind: .problem)
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
        presentNewSession(here: nil)
    }

    /// ⇧⌘N (v5 slice 3): the sheet on the attached session's host and
    /// folder — a fresh conversation where the work already is, which is
    /// how new sessions actually get started here. With nothing attached
    /// it is ⌘N. The row's context menu and `n` name the row directly.
    @objc func newSessionHereAction(_ sender: Any?) {
        presentNewSession(here: controller.poller.attachedRef)
    }

    private func presentNewSession(here ref: SessionRef?) {
        guard let window, newSessionSheet == nil else { return }
        let row = ref.flatMap { ref in controller.poller.state.rows.first { $0.ref == ref } }
        let model = NewSessionModel(
            hosts: controller.hosts.hosts,
            recentFolders: { [weak self] host in self?.recentFolders(on: host) ?? [] },
            shortCwd: { [weak self] cwd, host in self?.controller.hosts.shortCwd(cwd, host: host) ?? cwd },
            commandLine: { [weak self] host, request in
                guard let self, let cli = try? self.controller.cli(for: SessionRef(host: host, id: "-")) else { return "" }
                return cli.spawnCommandLine(request)
            },
            here: row.map { ($0.host, $0.session.cwd) })
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
                    // One pane: ⇧⌘N starts the new session beside the one on
                    // screen, and attach refuses while one is attached — so
                    // leave it first. `detach()` returns once the child has
                    // exited, which is what attach checks.
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

    /// Archive / pin (v4): the controller does what `ccc archive <ref>`
    /// does, and the answer — ours, or the far side's — is the notice.
    func mark(_ ref: SessionRef, _ change: MarkChange) {
        Task { @MainActor in
            do {
                showNotice(try await controller.mark(ref, change))
            } catch {
                showNotice("\(error)", kind: .problem)
            }
        }
    }

    /// The row's Merge submenu (v6): the controller does what `ccc merge
    /// <ref> --<strategy>` does, and its one sentence — merged, or why not
    /// — is the notice. A refusal is a problem: it stays until read.
    func merge(_ ref: SessionRef, _ strategy: MergeStrategy) {
        Task { @MainActor in
            do {
                let outcome = try await controller.merge(ref, strategy)
                showNotice(outcome.said, kind: outcome.merged ? .answer : .problem)
            } catch {
                showNotice("\(error)", kind: .problem)
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
            // What the row already knows (slice 2): say it before the
            // harness does, so "kept" is never a surprise.
            + ((row?.worktree?.unpushed ?? 0) > 0 ? "\n\(row!.worktree!.branch) has \(row!.worktree!.unpushed!) unpushed commit\(row!.worktree!.unpushed! == 1 ? "" : "s"); the harness will keep it." : "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { @MainActor in
            do {
                showNotice(try await controller.delete(ref))
            } catch {
                showNotice("\(error)", kind: .problem)
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
