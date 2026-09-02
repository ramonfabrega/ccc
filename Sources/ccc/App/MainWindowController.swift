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

    init(controller: PaneController) {
        self.controller = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "ccc"
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
        if !state.issues.isEmpty {
            parts.append("roster shape changed — showing what still decodes: " +
                         state.issues.prefix(3).map(\.description).joined(separator: "; ") +
                         (state.issues.count > 3 ? " (+\(state.issues.count - 3))" : ""))
        }
        let text = parts.joined(separator: "\n")
        if banner.stringValue != text { banner.stringValue = text }
        bannerBox.isHidden = text.isEmpty
    }

    func showNotice(_ text: String) {
        noticeText = text
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
        window?.title = "ccc — \(session.ref)"
    }

    private func unmount() {
        for view in paneContainer.subviews where view !== placeholder { view.removeFromSuperview() }
        placeholder.isHidden = false
        window?.title = "ccc"
    }

    private func attach(_ ref: SessionRef) {
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
