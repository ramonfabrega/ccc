import Foundation

/// One latency, as `ccc stats` needs it: how many, and the most recent
/// few — a median and a worst say more about how typing *feels* than a
/// mean over a session does.
public struct Latency: Codable, Sendable, Equatable {
    public var count: Int
    /// The most recent samples, oldest first, at most `Latency.window`.
    public var recentMs: [Double]

    public static let window = 64

    public init(count: Int = 0, recentMs: [Double] = []) {
        self.count = count
        self.recentMs = recentMs
    }

    public mutating func record(_ ms: Double) {
        count += 1
        recentMs.append(ms)
        if recentMs.count > Self.window { recentMs.removeFirst(recentMs.count - Self.window) }
    }

    public var medianMs: Double? {
        guard !recentMs.isEmpty else { return nil }
        let sorted = recentMs.sorted()
        return sorted[sorted.count / 2]
    }

    public var worstMs: Double? { recentMs.max() }
}

/// A keystroke in three parts, because "typing feels less smooth here
/// than over ssh" (Ramon, on air, 2026-11-13) names a sum and the parts
/// have different owners:
///
/// - `input`: the key event's own timestamp → our handler ran. Ours, and
///   only ours: it is the main thread being late.
/// - `echo`: the key's bytes written to the PTY → the first bytes back.
///   The hop and the harness — ssh, the attach client, the session's own
///   render — and nothing of the pane's.
/// - `draw`: those bytes read off the PTY → the frame carrying them
///   presented. Ours again: the hop to the main actor, the parse, the
///   pacing, the encode.
///
/// What a terminal over the same ssh would show is `echo` plus its own
/// `draw`; the first and third are where ccc can be slower than one.
public struct TypingStats: Codable, Sendable, Equatable {
    public var input: Latency
    public var echo: Latency
    public var draw: Latency

    public init(input: Latency = Latency(), echo: Latency = Latency(), draw: Latency = Latency()) {
        self.input = input
        self.echo = echo
        self.draw = draw
    }
}

/// The three clocks, kept apart from the session so the bookkeeping is a
/// test. Every time is seconds on one monotonic clock (`systemUptime`,
/// which is also what `NSEvent.timestamp` is on).
public struct TypingMeter: Sendable {
    public private(set) var stats = TypingStats()
    /// The first write nothing has answered yet.
    private var keyAt: Double?
    /// The first read no frame has shown yet.
    private var readAt: Double?

    /// A write this small is typing; anything larger is a paste or a
    /// script, and its "echo" is not a keystroke's.
    public static let typedBytes = 16
    /// An answer this late is not an answer to that key — a key that
    /// printed nothing, and then the session spoke for its own reasons.
    public static let echoBound = 2.0

    public init() {}

    /// The handler ran `lag` seconds after the event happened.
    public mutating func handled(lag: Double) {
        guard lag >= 0, lag < 5 else { return }
        stats.input.record(lag * 1000)
    }

    public mutating func wrote(bytes: Int, at now: Double) {
        guard bytes > 0, bytes <= Self.typedBytes else {
            keyAt = nil
            return
        }
        if keyAt == nil { keyAt = now }
    }

    public mutating func read(at now: Double) {
        if let key = keyAt {
            let waited = now - key
            if waited >= 0, waited < Self.echoBound { stats.echo.record(waited * 1000) }
            keyAt = nil
        }
        if readAt == nil { readAt = now }
    }

    public mutating func presented(at now: Double) {
        guard let read = readAt else { return }
        readAt = nil
        let took = now - read
        if took >= 0, took < 5 { stats.draw.record(took * 1000) }
    }
}
