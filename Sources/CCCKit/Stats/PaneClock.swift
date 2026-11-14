import Foundation

/// How long the window's pane has shown a session, and how long it has
/// had none — the roster at full width — `ccc stats`' `window` line.
///
/// It exists because that space was built into on an impression ("when
/// nothing is attached we have a big black screen") and an impression is
/// not a rate: a click attaches and ← keeps the session mounted, so the
/// pane is empty only after a launch, a detach, or a session ending.
/// Whether that is a tenth of the day or half of it decides what the
/// space is worth building into next, and nothing could say. `rowsRead`
/// is the other half: how many sessions were actually looked at there.
///
/// Only time the window is **on screen** counts. ccc is menubar-resident
/// and a closed window has an empty pane all night that nobody is looking
/// at; counted, it would say the empty state is the whole product.
///
/// Event-driven, not sampled: the three things that change the answer —
/// the window showing, a session mounting, a session leaving — each call
/// `set`, and a reading closes the open interval at the moment it is
/// asked. No timer runs for a number that is read a few times a day.
public struct PaneClock: Sendable, Equatable {
    public private(set) var visible = false
    public private(set) var attached = false
    private var since: Date?
    private var attachedSeconds = 0.0
    private var readingSeconds = 0.0
    private var rowsRead = 0
    private var lastRead: SessionRef?

    public init() {}

    public mutating func set(visible: Bool? = nil, attached: Bool? = nil, at now: Date = Date()) {
        close(at: now)
        if let visible { self.visible = visible }
        if let attached {
            self.attached = attached
            // Coming back to the full-width roster on the row that was just
            // left is a second look, and counts as one.
            if attached { lastRead = nil }
        }
        since = self.visible ? now : nil
    }

    /// `ref` is the selected row with no pane up. Counted once per row per stay:
    /// the 2 s poll redraws the same row all day and that is one read.
    public mutating func read(_ ref: SessionRef?) {
        guard visible, !attached, let ref, ref != lastRead else { return }
        lastRead = ref
        rowsRead += 1
    }

    private mutating func close(at now: Date) {
        guard let since else { return }
        let elapsed = max(0, now.timeIntervalSince(since))
        if attached { attachedSeconds += elapsed } else { readingSeconds += elapsed }
        self.since = now
    }

    public func stats(at now: Date = Date()) -> PaneTimeStats {
        var copy = self
        copy.close(at: now)
        return PaneTimeStats(attachedSeconds: copy.attachedSeconds, readingSeconds: copy.readingSeconds,
                             rowsRead: copy.rowsRead)
    }
}

/// `PaneClock`, as `ccc stats` carries it.
public struct PaneTimeStats: Codable, Sendable, Equatable {
    /// Window on screen with a session in the pane.
    public var attachedSeconds: Double
    /// Window on screen with nothing attached: the roster at full width.
    /// The name is from the two cuts where that state was a "reading
    /// pane", and it is the wire, so it stays.
    public var readingSeconds: Double
    /// Distinct rows selected with no pane up, one per stay on a row.
    public var rowsRead: Int

    public init(attachedSeconds: Double, readingSeconds: Double, rowsRead: Int) {
        self.attachedSeconds = attachedSeconds
        self.readingSeconds = readingSeconds
        self.rowsRead = rowsRead
    }

    /// The share of on-screen time the pane had no session in it, or nil
    /// before the window has been on screen at all.
    public var readingShare: Double? {
        let total = attachedSeconds + readingSeconds
        return total > 0 ? readingSeconds / total : nil
    }

    /// `window  attached 41m · reading 9m (18%) · 14 rows read` — `ccc
    /// stats`' line. Nil before the window has been on screen at all:
    /// three zeroes would read as a measurement.
    public var line: String? {
        guard let share = readingShare else { return nil }
        let rows = "\(rowsRead) row\(rowsRead == 1 ? "" : "s") read"
        return "window  attached \(SessionEvent.spell(attachedSeconds)) · reading \(SessionEvent.spell(readingSeconds))"
            + " (\(Int((share * 100).rounded()))%) · \(rows)"
    }
}
