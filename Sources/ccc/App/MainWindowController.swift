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
    /// The right side: the session pane, and under it — when one is open
    /// (v6 slice 4) — the shell pane, on a divider of their own.
    private let paneSplit = NSSplitView()
    private let paneContainer = NSView()
    private let shellContainer = NSView()
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
        window.minSize = NSSize(width: 800, height: 400)
        // ⌘W closes the window, not the app; the controller keeps it so the
        // menubar item, the Dock, ⌘0 and `ccc window show` bring it back.
        window.isReleasedWhenClosed = false
        super.init(window: window)
        // Where the window was last time. The autosave name was set on the
        // window before this line for eight versions and never once saved a
        // frame: `NSWindowController(window:)` **clears** `frameAutosaveName`
        // (probe: set it, hand the window to a controller, read it back —
        // empty) and turns cascading on, so every launch landed on the
        // contentRect above, which is the screen's bottom-left corner. Set
        // it after the controller has had the window, restore explicitly —
        // `setFrameAutosaveName` alone registers the save, it does not read
        // — and centre only when there is nothing saved to read.
        shouldCascadeWindows = false
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        window.setFrameAutosaveName(Self.frameName)
        build()
        controller.makeHost = { [weak self] cols, rows in
            let bounds = self?.paneContainer.bounds ?? CGRect(x: 0, y: 0, width: 8 * cols, height: 17 * rows)
            return PaneController.makeDefaultHost(frame: bounds)
        }
        controller.onSessionStarted = { [weak self] session in self?.mount(session) }
        controller.onSessionEnded = { [weak self] _ in self?.unmount() }
        // ← on an empty prompt (v7 slice 1): the harness's "back to the
        // agents view", answered here by the roster taking the keyboard
        // with the attached row selected, so ↑↓ move from where you are
        // and ⏎ or → return to the pane.
        controller.onLeaveRequested = { [weak self] in self?.focusRoster() }
        controller.onShellStarted = { [weak self] shell in self?.mountShell(shell) }
        controller.onShellEnded = { [weak self] in self?.unmountShell() }
        controller.defaultSize = gridSize()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: layout

    /// The defaults key the frame is saved under (`NSWindow Frame ccc.main`).
    /// Renaming it forgets every Mac's window position once.
    static let frameName = "ccc.main"
    /// The two dividers, remembered the way the frame is. AppKit's own
    /// `NSSplitView.autosaveName` is not used: it restores after layout and
    /// this window sets both dividers itself — the roster on the first
    /// pass, the shell's every time one opens — so the two would race and
    /// the loser would be whichever ran last. Ours are read where those
    /// positions are already being set.
    private static let rosterWidthKey = "ccc.rosterWidth"
    private static let shellHeightKey = "ccc.shellHeight"
    static let defaultRosterWidth: CGFloat = 420
    static let defaultShellHeight: CGFloat = 260

    private static func savedLength(_ key: String, default fallback: CGFloat) -> CGFloat {
        guard let saved = UserDefaults.standard.object(forKey: key) as? Double, saved > 0 else { return fallback }
        return CGFloat(saved)
    }

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
        let roster = NSHostingView(rootView: RosterView(poller: controller.poller, hosts: controller.hosts, focus: rosterFocus, attach: { [weak self] ref in
            self?.attach(ref)
        }, focusPane: { [weak self] in
            self?.focusPane()
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
        }, push: { [weak self] ref, target in
            self?.push(ref, target)
        }, update: { [weak self] ref in
            self?.update(ref)
        }, fetch: { [weak self] ref in
            self?.fetch(ref)
        }, pull: { [weak self] ref in
            self?.pull(ref)
        }, openShell: { [weak self] ref, atRepo in
            self?.openShell(ref, atRepo: atRepo)
        }, selectionChanged: { [weak self] ref in
            self?.currentSelection = ref
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
        // The session pane over the shell pane; the shell's box stays
        // hidden (collapsed by the split view) until a shell opens.
        paneSplit.isVertical = false
        paneSplit.dividerStyle = .thin
        shellContainer.wantsLayer = true
        shellContainer.layer?.backgroundColor = NSColor.black.cgColor
        shellContainer.isHidden = true
        paneSplit.addArrangedSubview(paneContainer)
        paneSplit.addArrangedSubview(shellContainer)
        paneContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        shellContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        split.addArrangedSubview(paneSplit)
        root.addArrangedSubview(split)
        split.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        roster.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        paneSplit.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        split.delegate = self
        let rosterWidth = Self.savedLength(Self.rosterWidthKey, default: Self.defaultRosterWidth)
        // Restoring is not choosing: `setPosition` runs through the same
        // delegate hook a drag does (measured — the launch and the command
        // both logged a `constrainSplitPosition`), so without the flag the
        // first launch would write the default back as if it had been
        // picked, and a later change to `defaultRosterWidth` would reach
        // nobody.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            restoringRosterWidth = true
            split.setPosition(rosterWidth, ofDividerAt: 0)
            restoringRosterWidth = false
        }
    }

    /// A sentence over the pane. An answer ("installed …", "archived a1b2")
    /// fades on its own; a problem stays until a click, because it is the
    /// guard talking. `for:` overrides the kind's own timing.
    func showNotice(_ text: String, kind: NoticeHUD.Kind = .answer, for duration: Duration?? = nil,
                    action: (title: String, run: () -> Void)? = nil) {
        hud.show(text, kind: kind, for: duration ?? kind.duration, action: action)
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
        // The overlapped switch (`PaneController.swap`) mounts the incoming
        // pane while the outgoing one is still on screen, drawn and holding
        // the keyboard — so clearing the old view is this method's job, not
        // `unmount`'s. Both happen inside one layout pass, which is what
        // makes the change read as a swap rather than as a teardown and a
        // build: there is no frame in between showing neither.
        for old in paneContainer.subviews
        where old !== placeholder && old !== hud && old !== view {
            old.removeFromSuperview()
        }
        placeholder.isHidden = true
        place(session, in: paneContainer)
        hud.keepOnTop()
        window?.makeFirstResponder(view)
        window?.title = "\(BuildInfo.current.appTitle) — \(session.ref)"
    }

    /// The shell pane (v6 slice 4): the same mounting under the session,
    /// at the height the last drag left, and the keyboard.
    private func mountShell(_ shell: AttachSession) {
        guard let view = shell.host.view else { return }
        // Unhide, lay out, *then* place the divider: set before the split
        // has laid out it lands on the session's minimum and the shell
        // takes the rest (seen on the first open, 2026-09-02). The session
        // holds less than the shell, so a window resize flexes the session.
        shellContainer.isHidden = false
        paneSplit.setHoldingPriority(NSLayoutConstraint.Priority(250), forSubviewAt: 0)
        paneSplit.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 1)
        paneSplit.layoutSubtreeIfNeeded()
        let total = paneSplit.bounds.height
        paneSplit.setPosition(max(120, total - shellHeight - paneSplit.dividerThickness), ofDividerAt: 0)
        paneSplit.layoutSubtreeIfNeeded()
        place(shell, in: shellContainer)
        window?.makeFirstResponder(view)
    }

    private var shellHeight = MainWindowController.savedLength(MainWindowController.shellHeightKey,
                                                               default: MainWindowController.defaultShellHeight)

    private func unmountShell() {
        if !shellContainer.isHidden {
            shellHeight = max(80, shellContainer.bounds.height)
            UserDefaults.standard.set(Double(shellHeight), forKey: Self.shellHeightKey)
        }
        for view in shellContainer.subviews { view.removeFromSuperview() }
        shellContainer.isHidden = true
        // The keyboard goes back to the session, if one is on screen.
        if let view = controller.session?.host.view, view.superview != nil { window?.makeFirstResponder(view) }
    }

    /// Inset once; the autoresizing mask keeps the gutter as the window
    /// resizes. The pane knows nothing of it — its view is its bounds —
    /// so `peek`'s composite and the mouse's cell math stay right. Then
    /// make the child hear the size the view actually got.
    private func place(_ session: AttachSession, in container: NSView) {
        guard let view = session.host.view else { return }
        view.frame = Self.paneFrame(in: container.bounds)
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
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
        // ⏎ on the row already attached: the keyboard goes back to the
        // pane, which is what ← from the pane left for.
        if let session = controller.session, session.isRunning, session.ref == ref {
            focusPane()
            return
        }
        controller.defaultSize = gridSize()
        Task { @MainActor in
            // The switch keeps the old session on screen until the new one
            // has painted (`PaneController.swap`), so a slow attach looks
            // like the click did nothing. Say what is happening — but only
            // once it *is* slow. A local attach lands well inside this and
            // stays silent, which is the whole point of the overlap: the
            // fast path has no chrome at all.
            let waking = "Waking \(self.name(of: ref))…"
            let notice = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                self?.showNotice(waking, for: .some(nil))
            }
            do {
                _ = try await controller.switchTo(ref: ref)
                notice.cancel()
                // Only if it is still the waking sentence on screen: the
                // wait's own notice goes when the wait does, and never
                // takes something else's place with it.
                hud.dismiss(ifShowing: waking)
            } catch {
                notice.cancel()
                showNotice("\(error)", kind: .problem)
            }
        }
    }

    /// The row's name if the roster has one, else the id — what a sentence
    /// about a session should call it.
    private func name(of ref: SessionRef) -> String {
        controller.poller.state.rows.first { $0.ref == ref }?.session.name ?? ref.id
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
            cancel: { [weak self] in self?.dismissNewSession() },
            addHost: { [weak self] in self?.addHostAction(nil) })))
        newSessionSheet = sheet
        window.beginSheet(sheet)
    }

    private func dismissNewSession() {
        guard let window, let sheet = newSessionSheet else { return }
        window.endSheet(sheet)
        newSessionSheet = nil
    }

    private var addHostSheet: NSWindow?

    /// The picker (queue item 3). Reached from the app menu and from the New
    /// Session sheet's host row, which is the moment it is actually wanted.
    ///
    /// Nothing is passed in and nothing comes back: the sheet writes through
    /// `HostSetup.add` to `hosts.json`, and the host list is hot-reloaded, so
    /// a host added here reaches the running app the way `ccc hosts add`
    /// already does (v9 slice 1's fix). That is why this can be a leaf.
    @objc func addHostAction(_ sender: Any?) {
        guard let window, addHostSheet == nil else { return }
        // From the New Session sheet, the picker is a sheet *on* it, so the
        // host list underneath is still there to come back to.
        let parent = newSessionSheet ?? window
        let sheet = NSWindow(contentViewController: NSHostingController(
            rootView: AddHostView(onClose: { [weak self] in self?.dismissAddHost() })))
        addHostSheet = sheet
        parent.beginSheet(sheet)
    }

    private func dismissAddHost() {
        guard let sheet = addHostSheet else { return }
        (newSessionSheet ?? window)?.endSheet(sheet)
        addHostSheet = nil
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
                    // screen; the switch leaves that one first.
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

    /// Open in Terminal (v6 slice 4): from the row's menu, `t` on the
    /// selected row, or ⌘T for the attached session (else the selected
    /// row). An open shell is focused rather than doubled.
    func openShell(_ ref: SessionRef, atRepo: Bool = false) {
        Task { @MainActor in
            do {
                let result = try await controller.openShell(ref, atRepo: atRepo, cols: gridSize().cols)
                if result.opened {
                    showNotice(result.said)
                } else {
                    if let view = controller.shell?.host.view { window?.makeFirstResponder(view) }
                    // "already open" needs no sentence; "running something" does.
                    if result.said.contains("running") { showNotice(result.said, kind: .problem) }
                }
            } catch {
                showNotice("\(error)", kind: .problem)
            }
        }
    }

    @objc func openShellAction(_ sender: Any?) {
        guard let ref = controller.poller.attachedRef ?? currentSelection else {
            showNotice("select or attach a session first", kind: .problem)
            return
        }
        openShell(ref)
    }

    /// ⌥⌘T: the same, at the repository's main checkout — where the
    /// nightly `git merge --ff-only` and `scripts/install` actually run.
    @objc func openRepoShellAction(_ sender: Any?) {
        guard let ref = controller.poller.attachedRef ?? currentSelection else {
            showNotice("select or attach a session first", kind: .problem)
            return
        }
        openShell(ref, atRepo: true)
    }

    @objc func closeShellAction(_ sender: Any?) {
        if !controller.closeShell() { showNotice("no shell pane is open", kind: .problem) }
    }

    /// The roster's selection, for ⌘T when nothing is attached.
    private var currentSelection: SessionRef?

    // MARK: keyboard between the roster and the pane (v7 slice 1)

    private let rosterFocus = RosterFocus()

    /// The roster takes the keyboard, with the attached row selected.
    /// SwiftUI owns the list's focus, so this is a request the view
    /// answers (`RosterFocus`), not a `makeFirstResponder` from here.
    private func focusRoster() {
        rosterFocus.request(selecting: controller.poller.attachedRef)
    }

    /// The pane takes the keyboard back: → or ⏎ on the attached row.
    private func focusPane() {
        guard let view = controller.session?.host.view, view.superview != nil else { return }
        window?.makeFirstResponder(view)
    }

    /// Update from master (v6 slice 6): the controller does what `ccc
    /// update <ref>` does. Updated is an answer; a refusal is a problem;
    /// and a conflict is a problem that offers the one thing the menu
    /// cannot do — **Ask the session to merge master** — a button on the
    /// notice that attaches the pane to the session and types the prompt
    /// the outcome carries (`ccc update --ask` is its twin).
    func update(_ ref: SessionRef) {
        Task { @MainActor in
            do {
                let outcome = try await controller.update(ref)
                if let prompt = outcome.ask {
                    let base = controller.poller.state.rows.first { $0.ref == ref }?.worktree?.base ?? "master"
                    showNotice(outcome.said, kind: .problem, action: ("Ask the session to merge \(base)", { [weak self] in
                        self?.ask(ref, prompt: prompt)
                    }))
                } else {
                    showNotice(outcome.said, kind: outcome.merged ? .answer : .problem)
                }
            } catch {
                showNotice("\(error)", kind: .problem)
            }
        }
    }

    /// The button's press: attach and type. The answer names what was
    /// asked, so the sentence on screen and the pane agree.
    func ask(_ ref: SessionRef, prompt: String) {
        Task { @MainActor in
            do {
                showNotice(try await controller.ask(ref, prompt: prompt))
            } catch {
                showNotice("\(error)", kind: .problem)
            }
        }
    }

    /// Fetch and Pull master (v6 slice 7): the same sentence shape as
    /// push — what happened, or why not — as the notice.
    func fetch(_ ref: SessionRef) {
        Task { @MainActor in
            do {
                let outcome = try await controller.fetch(ref)
                showNotice(outcome.said, kind: outcome.merged ? .answer : .problem)
            } catch {
                showNotice("\(error)", kind: .problem)
            }
        }
    }

    func pull(_ ref: SessionRef) {
        Task { @MainActor in
            do {
                let outcome = try await controller.pull(ref)
                showNotice(outcome.said, kind: outcome.merged ? .answer : .problem)
            } catch {
                showNotice("\(error)", kind: .problem)
            }
        }
    }

    /// The submenu's Push items (v6 slice 3): the same sentence shape as
    /// merge — pushed, or why not — as the notice.
    func push(_ ref: SessionRef, _ target: PushTarget) {
        Task { @MainActor in
            do {
                let outcome = try await controller.push(ref, target)
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
        // A miniaturized window answers `makeKeyAndOrderFront` by staying in
        // the Dock, so the menubar item and `ccc window show` would both
        // look broken on the one state a person cannot click their way out
        // of from here.
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// The recovery gesture, and the one the first launch performs: a window
    /// that came back from a display that is gone, or was moved somewhere
    /// its title bar cannot be grabbed, is one command or one menu item away
    /// from the middle of the screen.
    @objc func centerAction(_ sender: Any?) {
        window?.center()
    }

    /// The desktop's top edge in AppKit's coordinates. Every window
    /// coordinate that crosses the socket — read or written — is measured
    /// down from here, because that is the space `screencapture -R` and
    /// CGWindow use and the pane's rect was already in. AppKit's own is the
    /// other way up; the conversion lives here and nowhere else.
    private static var desktopTop: Double { Double(NSScreen.screens.first?.frame.maxY ?? 0) }

    private static func frame(topLeft x: Double, _ y: Double, size: NSSize) -> NSRect {
        NSRect(x: x,
               y: WindowGeometry.appKitY(topLeftY: y, height: size.height, desktopTop: desktopTop),
               width: size.width, height: size.height)
    }

    private static func topLeft(of window: NSWindow) -> (x: Double, y: Double) {
        (Double(window.frame.minX),
         WindowGeometry.topLeftY(frameMaxY: window.frame.maxY, desktopTop: desktopTop))
    }

    /// The socket's window verbs: **one per gesture the title bar has**.
    /// `close` is literally ⌘W, `minimize` the yellow button, `zoom` the
    /// green one, `fullscreen` its other reading, `move` a drag on the bar,
    /// `resize` a drag on the corner (check 5's twin: the pane and the child
    /// must follow the new grid), `frame` the two at once, `split` a drag on
    /// the roster's divider. They land where `ccc geometry` reads — same
    /// numbers, same space — and the four that place something are kept
    /// across a relaunch, because neither the autosave nor the divider's
    /// delegate cares whose hand moved it.
    func windowAction(_ action: String) -> Bool {
        guard let window, let action = WindowAction(action) else { return false }
        switch action {
        case .show: showAction(nil)
        case .hide: window.orderOut(nil)
        case .close: window.performClose(nil)
        case .minimize: window.miniaturize(nil)
        case .zoom: window.zoom(nil)
        case .fullScreen: window.toggleFullScreen(nil)
        case .center: centerAction(nil)
        // The picker's twin for *opening* it. The picker's own work already
        // has twins (`ccc hosts discover`, `ccc hosts add`); this is what
        // lets `ccc peek` see the sheet, which is the only way to judge a
        // window from a machine with no screen.
        case .addHost: addHostAction(nil)
        // Its gestures already have twins (`ccc spawn` runs what Start
        // runs); this opens the sheet so `peek` can see it, which since
        // sheets are composited is the only way to judge one with no screen.
        case .newSession: newSessionAction(nil)
        case .move(let x, let y):
            window.setFrame(Self.frame(topLeft: x, y, size: window.frame.size), display: true, animate: false)
        case .resize(let width, let height):
            // The top-left stays put, which is what dragging the bottom-right
            // corner does — and what makes `resize` composable with `move`.
            let corner = Self.topLeft(of: window)
            window.setFrame(Self.frame(topLeft: corner.x, corner.y, size: NSSize(width: width, height: height)),
                            display: true, animate: false)
        case .frame(let x, let y, let width, let height):
            window.setFrame(Self.frame(topLeft: x, y, size: NSSize(width: width, height: height)),
                            display: true, animate: false)
        case .split(let width):
            split.setPosition(CGFloat(width), ofDividerAt: 0)
            rememberRosterWidth(CGFloat(width))
        }
        return true
    }

    /// The width the divider was put at, saved. The drag's delegate and
    /// `ccc window split` both come through here, so the gesture and its
    /// twin cannot disagree about what is remembered.
    /// True only while the launch is putting the divider back where it was.
    private var restoringRosterWidth = false

    private func rememberRosterWidth(_ width: CGFloat) {
        guard width >= 320 else { return }
        UserDefaults.standard.set(Double(width), forKey: Self.rosterWidthKey)
    }


    @objc func refreshAction(_ sender: Any?) {
        Task { await controller.poller.tick() }
    }

    /// The whole window as PNG via our own view hierarchy — TCC-free eyes on
    /// our UI (scry's `peek --window`). Material backgrounds render black;
    /// layout and the pane composite correctly, which is what matters.
    /// The window's id and where its pane sits (v8 slice 3) — what `ccc
    /// capture` aims `screencapture -l` at, and what turns a cell into a
    /// pixel. `windowNumber` is the `CGWindowID`: it was always here, it
    /// just had no way out of the app.
    ///
    /// Everything is relative to the *window*, not the content view,
    /// because a window capture includes the title bar and a caller
    /// indexes the image it actually gets.
    func geometry() -> WindowGeometry? {
        guard let window else { return nil }
        let frame = window.frame
        var pane: WindowGeometry.Pane?
        if let session = controller.session, let view = session.host.view, view.window === window,
           let ghostty = session.host as? GhosttyPane {
            // Window base coordinates, then flipped: AppKit measures up
            // from the bottom, an image is indexed down from the top.
            let inWindow = view.convert(view.bounds, to: nil)
            let metrics = ghostty.metrics
            let size = ghostty.size
            pane = WindowGeometry.Pane(
                x: inWindow.minX, y: frame.height - inWindow.maxY,
                width: inWindow.width, height: inWindow.height,
                cols: size.cols, rows: size.rows,
                cellWidth: metrics.width, cellHeight: metrics.height)
        }
        let desktopTop = Double(Self.desktopTop)
        return WindowGeometry(
            windowID: window.windowNumber, scale: window.backingScaleFactor,
            x: frame.minX, y: WindowGeometry.topLeftY(frameMaxY: frame.maxY, desktopTop: desktopTop),
            width: frame.width, height: frame.height,
            visible: window.isVisible, minimized: window.isMiniaturized,
            zoomed: window.isZoomed, fullScreen: window.styleMask.contains(.fullScreen),
            rosterWidth: Double(split.arrangedSubviews.first?.frame.width ?? 0), pane: pane)
    }

    func peek() -> Data? {
        guard let window, let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return nil }
        content.cacheDisplay(in: content.bounds, to: rep)
        // A Metal layer is invisible to cacheDisplay; composite the pane's
        // own offscreen render into its place so peek shows the v1 pane too.
        for live in [controller.session, controller.shell].compactMap({ $0 }) {
            guard let pane = live.host as? GhosttyPane, let view = pane.view, view.window != nil,
                  let image = pane.snapshotImage(), let context = NSGraphicsContext(bitmapImageRep: rep) else { continue }
            let frameInContent = view.convert(view.bounds, to: content)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            // cacheDisplay draws in the content view's coordinate space (flipped or not);
            // NSBitmapImageRep contexts are bottom-left, so flip y for a non-flipped content view.
            let y = content.isFlipped ? content.bounds.height - frameInContent.maxY : frameInContent.minY
            context.cgContext.draw(image, in: CGRect(x: frameInContent.minX, y: y, width: frameInContent.width, height: frameInContent.height))
            NSGraphicsContext.restoreGraphicsState()
        }
        // A sheet is its own NSWindow, so it is not in this hierarchy at all
        // and every sheet the app has ever shown was invisible to `peek`.
        // Composited here in its real place, which is what makes the New
        // Session sheet and the host picker judgeable from a machine with no
        // screen — the same reason `peek` composites the Metal pane above.
        for sheet in window.sheets {
            guard let sheetContent = sheet.contentView,
                  let sheetRep = sheetContent.bitmapImageRepForCachingDisplay(in: sheetContent.bounds),
                  let context = NSGraphicsContext(bitmapImageRep: rep) else { continue }
            sheetContent.cacheDisplay(in: sheetContent.bounds, to: sheetRep)
            guard let image = sheetRep.cgImage else { continue }
            // Sheet frames are in screen coordinates; the window's own frame
            // turns them into content-view ones.
            let origin = content.convert(
                CGPoint(x: sheet.frame.minX - window.frame.minX, y: sheet.frame.minY - window.frame.minY),
                from: nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            let y = content.isFlipped
                ? content.bounds.height - (origin.y + sheet.frame.height) : origin.y
            context.cgContext.draw(
                image,
                in: CGRect(x: origin.x, y: y, width: sheet.frame.width, height: sheet.frame.height))
            NSGraphicsContext.restoreGraphicsState()
        }
        return rep.representation(using: .png, properties: [:])
    }
}

extension MainWindowController: NSSplitViewDelegate {
    /// A drag on the roster's divider is kept the way a drag on the window's
    /// edge is — the same gesture, so the same promise.
    ///
    /// **A squeeze is not a preference**, which is why this is the hook and
    /// `splitViewDidResizeSubviews` is not. That notification fires for a
    /// window resize too, and narrowing the window pins the roster at its
    /// 320pt minimum: saved, one small window would make a narrow roster
    /// permanent (measured — `ccc window resize 900 600` wrote 320, then
    /// 351). Neither `NSSplitViewDividerIndex` nor the split's own width
    /// separates the two: since macOS 12 the key is in the user info of
    /// both, and a resize posts several passes, one of which has the width
    /// the pass before it settled on. This method is called *only while a
    /// divider is being dragged*, so it does not have to separate anything.
    /// The position is returned untouched — the constraint is not ours, the
    /// arranged subviews' minimum widths already hold the line.
    ///
    /// What the window takes away it gives back: the remembered width is
    /// re-applied at the next launch, and squeezed again only if it still
    /// has to be.
    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView === split, dividerIndex == 0, !restoringRosterWidth { rememberRosterWidth(proposedPosition) }
        return proposedPosition
    }
}
