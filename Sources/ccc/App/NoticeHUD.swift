import AppKit

/// The answer to a click, floating over the pane: "pinned a1b2",
/// "fast-forwarded worktree-v2 → master", or why it refused. Xcode's build
/// HUD and Finder's copy progress are the shape — a material capsule, a
/// symbol, one sentence — and the reason it floats is the pane: a strip in
/// the window's stack (the banner, until 2026-09-02) resized the pane for
/// every sentence, which resized the PTY, which reflowed the TUI. This
/// view overlays the grid and never changes its size.
///
/// An answer fades on its own; a problem stays until clicked, because it
/// is the guard talking and worth a look. Conditions — a host down, the
/// roster's shape changed — are not answers and do not come here: they
/// live in the roster, beside the rows they are about.
@MainActor
final class NoticeHUD: NSVisualEffectView {
    enum Kind {
        case answer, problem

        var symbol: String { self == .answer ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" }
        var tint: NSColor { self == .answer ? .systemGreen : .systemOrange }
        /// How long it stays: an answer six seconds, a problem until a click.
        var duration: Duration? { self == .answer ? .seconds(6) : nil }
    }

    private let symbol = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    /// The one thing a problem can offer besides its sentence (slice 6:
    /// "Ask the session to merge master"). Hidden when there is none.
    private let button = NSButton(title: "", target: nil, action: nil)
    private var action: (() -> Void)?
    private var hideTask: Task<Void, Never>?
    /// Bumped by every show, so a fade-out that finishes after a newer show
    /// does not hide the newer notice.
    private var generation = 0

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        alphaValue = 0
        isHidden = true

        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
        symbol.setContentHuggingPriority(.required, for: .horizontal)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 4
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.target = self
        button.action = #selector(act(_:))
        button.isHidden = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        // A row: symbol, sentence, then the offer when there is one. The
        // stack drops a hidden button from the layout, so a plain notice
        // is the capsule it always was.
        let row = NSStackView(views: [symbol, label, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked(_:))))
        toolTip = "Click to dismiss"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Pin it to the top center of `container`, at most four fifths of its
    /// width, above every other subview. `keepOnTop()` re-asserts the
    /// order after the pane mounts its view.
    func install(in container: NSView) {
        container.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: container.centerXAnchor),
            topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.8),
        ])
    }

    func keepOnTop() {
        guard let container = superview else { return }
        container.addSubview(self, positioned: .above, relativeTo: nil)
    }

    /// `action`: a button after the sentence; pressing it runs the closure
    /// and dismisses the notice. Only a problem has one — it is the guard
    /// offering the way past itself.
    func show(_ text: String, kind: Kind, for duration: Duration?, action: (title: String, run: () -> Void)? = nil) {
        generation += 1
        let mine = generation
        hideTask?.cancel()
        hideTask = nil
        label.stringValue = text
        self.action = action?.run
        button.title = action?.title ?? ""
        button.isHidden = action == nil
        symbol.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: kind == .answer ? "done" : "problem")
        symbol.contentTintColor = kind.tint
        isHidden = false
        keepOnTop()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.motion(0.15)
            animator().alphaValue = 1
        }
        guard let duration else { return }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.generation == mine else { return }
            self.dismiss()
        }
    }

    func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        let mine = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.motion(0.25)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == mine else { return }
                self.isHidden = true
            }
        })
    }

    @objc private func clicked(_ sender: Any?) {
        dismiss()
    }

    @objc private func act(_ sender: Any?) {
        let run = action
        dismiss()
        run?()
    }

    /// Zero when the system asks for less motion.
    private static func motion(_ seconds: Double) -> Double {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : seconds
    }
}
