import Foundation
import GhosttyVt

/// The hand behind a selection (item 13). `GhosttyHost.select` is the
/// *destination* — two points and a grain — and this is the state machine
/// that turns a stream of pointer events into those points: press, drag,
/// release, with the click sequence (single → cell, double → word, triple →
/// line) counted by the core rather than by us.
///
/// It is the core's job for the same reason keys are (CLAUDE.md): word
/// boundaries, line trimming, reversed drags and rectangle corners are all
/// rules Ghostty already has and that we would get subtly wrong.
/// `selection.h` ships the whole machine — `ghostty_selection_gesture_event`
/// with typed press/drag/release events — so this file is a lifetime wrapper
/// and a coordinate conversion, and no selection logic at all.
///
/// Shaped after `GhosttyMouse`: one gesture and one reusable event per type
/// for the lifetime of the object, and a **strong** reference to the host so
/// the raw terminal handle cannot be freed under us —
/// `ghostty_selection_gesture_free` needs that terminal to release the
/// tracked refs the gesture holds, so a dead host here would leak them.
@MainActor
public final class GhosttySelectGesture {
    /// What a drag reads the pointer against: the grid's width in columns and
    /// the surface's size in **pixels**, which is the space
    /// `GhosttySurfacePosition` is expressed in. The core needs it to decide
    /// when a drag has left the grid (and, later, to ask for autoscroll).
    public struct Geometry: Equatable {
        public var columns: Int
        public var cellWidth: Int
        public var paddingLeft: Int
        public var screenHeight: Int

        public init(columns: Int, cellWidth: Int, paddingLeft: Int = 0, screenHeight: Int) {
            self.columns = columns
            self.cellWidth = cellWidth
            self.paddingLeft = paddingLeft
            self.screenHeight = screenHeight
        }

        var raw: GhosttySelectionGestureGeometry {
            GhosttySelectionGestureGeometry(
                columns: UInt32(clamping: max(1, columns)),
                cell_width: UInt32(clamping: max(1, cellWidth)),
                padding_left: UInt32(clamping: max(0, paddingLeft)),
                screen_height: UInt32(clamping: max(1, screenHeight))
            )
        }
    }

    /// Strong, and documented above: `ghostty_selection_gesture_free` takes
    /// the terminal the gesture last ran against.
    private let host: GhosttyHost
    private var gesture: GhosttySelectionGesture?
    private var pressEvent: GhosttySelectionGestureEvent?
    private var dragEvent: GhosttySelectionGestureEvent?
    private var releaseEvent: GhosttySelectionGestureEvent?

    public private(set) var lastError: String?

    public init(host: GhosttyHost) {
        self.host = host
        var g: GhosttySelectionGesture?
        if ghostty_selection_gesture_new(nil, &g) == GHOSTTY_SUCCESS, let g {
            gesture = g
        } else {
            lastError = "ghostty_selection_gesture_new failed"
        }
        pressEvent = Self.event(GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_PRESS)
        dragEvent = Self.event(GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_DRAG)
        releaseEvent = Self.event(GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_RELEASE)
    }

    private static func event(_ type: GhosttySelectionGestureEventType) -> GhosttySelectionGestureEvent? {
        var e: GhosttySelectionGestureEvent?
        guard ghostty_selection_gesture_event_new(nil, &e, type) == GHOSTTY_SUCCESS else { return nil }
        return e
    }

    isolated deinit {
        if let pressEvent { ghostty_selection_gesture_event_free(pressEvent) }
        if let dragEvent { ghostty_selection_gesture_event_free(dragEvent) }
        if let releaseEvent { ghostty_selection_gesture_event_free(releaseEvent) }
        // The host is still alive (we hold it), so the terminal is the live
        // one the gesture tracked against — which is exactly what the free
        // wants; NULL is only for a terminal that already went away.
        if let gesture { ghostty_selection_gesture_free(gesture, host.terminal) }
    }

    // MARK: state

    /// 1 for a single click, 2 for a double, 3 for a triple; 0 when no click
    /// sequence is active. The core counts this from the times we pass to
    /// `press`, so it is the same number that chose the behaviour.
    public var clickCount: Int {
        guard let gesture, let terminal = host.terminal else { return 0 }
        var count: UInt8 = 0
        guard ghostty_selection_gesture_get(gesture, terminal, GHOSTTY_SELECTION_GESTURE_DATA_CLICK_COUNT, &count) == GHOSTTY_SUCCESS else { return 0 }
        return Int(count)
    }

    /// Whether the current (or last) left-click gesture ever moved. A press
    /// and release with this false is a *click*, which is what tells the pane
    /// to clear the selection rather than keep a one-cell one.
    public var dragged: Bool {
        guard let gesture, let terminal = host.terminal else { return false }
        var moved = false
        guard ghostty_selection_gesture_get(gesture, terminal, GHOSTTY_SELECTION_GESTURE_DATA_DRAGGED, &moved) == GHOSTTY_SUCCESS else { return false }
        return moved
    }

    /// Cancel the click sequence and drop the tracked refs it holds. The
    /// selection on screen is not touched — clearing that is the host's job.
    public func reset() {
        guard let gesture, let terminal = host.terminal else { return }
        ghostty_selection_gesture_reset(gesture, terminal)
    }

    // MARK: events

    /// A press at a cell. `time` is what makes a double-click possible at all
    /// — the header is explicit that an untimed press can only ever be a
    /// single click — so an `NSEvent.timestamp` goes in here.
    ///
    /// Returns true when a selection came out and was installed: a press does
    /// produce one under word and line behaviour (double and triple click),
    /// and none for a plain single click, which only sets the anchor.
    @discardableResult
    public func press(
        col: Int, row: Int,
        position: CGPoint? = nil,
        time: TimeInterval? = nil,
        repeatInterval: TimeInterval = 0.5,
        repeatDistance: Double = 6
    ) -> Bool {
        guard let event = pressEvent, let ref = host.gridRef(col: col, row: row) else { return false }
        set(event, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, ref)
        setPosition(event, position)
        if let time {
            set(event, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_TIME_NS, UInt64(max(0, time) * 1_000_000_000))
            set(event, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REPEAT_INTERVAL_NS, UInt64(max(0, repeatInterval) * 1_000_000_000))
            set(event, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REPEAT_DISTANCE, repeatDistance)
        } else {
            clear(event, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_TIME_NS)
        }
        return apply(event)
    }

    /// A drag to a cell. Geometry is required by the core; `rectangle` is the
    /// ⌥ half of the gesture and is read per event, so a modifier picked up
    /// mid-drag changes the shape without restarting it.
    @discardableResult
    public func drag(col: Int, row: Int, position: CGPoint? = nil, geometry: Geometry, rectangle: Bool = false) -> Bool {
        guard let event = dragEvent, let ref = host.gridRef(col: col, row: row) else { return false }
        set(event, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, ref)
        setPosition(event, position)
        set(event, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_GEOMETRY, geometry.raw)
        set(event, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_RECTANGLE, rectangle)
        return apply(event)
    }

    /// A release, which ends the drag but keeps the click sequence alive so
    /// the next press can be the second of a double. Produces no selection —
    /// the header says so, and what is on screen already is the answer.
    public func release(col: Int? = nil, row: Int? = nil) {
        guard let event = releaseEvent else { return }
        if let col, let row, let ref = host.gridRef(col: col, row: row) {
            set(event, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, ref)
        } else {
            clear(event, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF)
        }
        _ = apply(event)
    }

    // MARK: plumbing

    /// Run one event and install whatever selection it produced.
    ///
    /// `GHOSTTY_NO_VALUE` is not a failure: it is what a release answers, and
    /// what a single-click press answers, and in both cases the gesture state
    /// was still updated. Only a selection that actually came out is
    /// installed, so a press never wipes a selection the caller meant to keep.
    @discardableResult
    private func apply(_ event: GhosttySelectionGestureEvent) -> Bool {
        guard let gesture, let terminal = host.terminal else { return false }
        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        let result = ghostty_selection_gesture_event(gesture, terminal, event, &selection)
        guard result == GHOSTTY_SUCCESS else {
            if result != GHOSTTY_NO_VALUE { lastError = "ghostty_selection_gesture_event: \(result.rawValue)" }
            return false
        }
        return host.install(selection: selection)
    }

    /// Every option is "a pointer to a value of the type the header names",
    /// so one generic setter covers all of them. `withUnsafePointer` rather
    /// than `&value`: the latter warns that a `T` might hold an object
    /// reference, and these are all plain C structs and scalars.
    private func set<T>(_ event: GhosttySelectionGestureEvent, _ option: GhosttySelectionGestureEventOption, _ value: T) {
        withUnsafePointer(to: value) {
            _ = ghostty_selection_gesture_event_set(event, option, UnsafeRawPointer($0))
        }
    }

    private func clear(_ event: GhosttySelectionGestureEvent, _ option: GhosttySelectionGestureEventOption) {
        _ = ghostty_selection_gesture_event_set(event, option, nil)
    }

    private func setPosition(_ event: GhosttySelectionGestureEvent, _ position: CGPoint?) {
        guard let position else {
            clear(event, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_POSITION)
            return
        }
        set(event, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_POSITION,
            GhosttySurfacePosition(x: Double(position.x), y: Double(position.y)))
    }
}
