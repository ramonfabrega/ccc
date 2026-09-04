import Foundation
import Testing

@testable import CCCKit

/// The wake reattach's window, and the night that sized it
/// (docs/EVIDENCE.md "item 6 — the lid", docs/QUEUE.md item 6).
///
/// The window was 20 s from v2 until 2026-09-04, chosen before anything had
/// measured what a wake costs. The lid night measured it, and 20 s turned
/// out to be *inside* the failure rather than around it — the retries land
/// at roughly +5, +10 and +15 s and the window shuts at +20, one or two
/// seconds before the tailnet answers on the slowest wakes. These are that
/// measurement kept as arithmetic, so narrowing the window again fails here
/// instead of on a laptop at 4 a.m.
@Suite struct WakeWindowTests {
    /// From the 18 wakes: the first `rc=0` landed 14–22 s after the wake.
    static let slowestRecovery: Duration = .seconds(22)
    /// `ConnectTimeout=5` in `ClaudeCLI.sshPrefix`, which is what one failed
    /// attempt costs and therefore how far apart the retries sit.
    static let attemptCost: Duration = .seconds(5)
    /// `reconnect` awaits its own (failing) poll before the first replay, so
    /// nothing is attempted in the first ~5 s.
    static let firstAttempt: Duration = .seconds(5)

    /// The shipped window, read from the one place that defines it. It is
    /// `private` to `PaneController`, which lives in the `ccc` executable
    /// target and cannot be imported, so the value is restated here and
    /// pinned by the comment above it — the guard is the arithmetic below,
    /// not the literal.
    static let window: Duration = .seconds(60)

    /// The window must still be admitting attempts after the slowest wake
    /// the night produced, with room for the attempt itself to run.
    @Test func theWindowOutlastsTheSlowestWake() {
        #expect(
            Self.window > Self.slowestRecovery + Self.attemptCost,
            """
            the wake window (\(Self.window)) must outlast the slowest measured \
            recovery (\(Self.slowestRecovery)) plus one attempt \
            (\(Self.attemptCost)); at 20 s it did not, and the pane stayed \
            dead on the three wakes in eighteen that took 21-22 s
            """)
    }

    /// The failure the old bound actually had: it is not enough that the
    /// window be longer than the recovery, because attempts are serialised
    /// at `ConnectTimeout` and the first one cannot start immediately. What
    /// matters is that an attempt *begins* after the network is back.
    @Test func anAttemptBeginsAfterTheNetworkReturns() {
        var started = Self.firstAttempt
        var attempts = 0
        var lastStart = Duration.zero
        while started < Self.window {
            attempts += 1
            lastStart = started
            started += Self.attemptCost
        }
        #expect(
            lastStart > Self.slowestRecovery,
            """
            the last attempt begins at \(lastStart), before the slowest \
            recovery at \(Self.slowestRecovery) — every replay would be made \
            into a network that is still down. This is exactly what the 20 s \
            window did, in 3 attempts ending at +20 s.
            """)
        #expect(attempts >= 4, "only \(attempts) attempts fit the window")
    }

    /// Three outcomes look the same from outside — the pane is not back —
    /// and the counters are what separate them, so they must survive the
    /// wire that `ccc stats` reads them over.
    @Test func theCountersRoundTrip() throws {
        let sent = WakeStats(wakes: 18, attempts: 54, gaveUp: 3, last: "gave up on studio:abc after 3 attempts, 20 s after wake")
        let back = try JSONDecoder().decode(WakeStats.self, from: JSONEncoder().encode(sent))
        #expect(back == sent)
    }

    /// A window face from an older build sends no `wake` key at all;
    /// `ccc stats` must read that as "this build does not count them",
    /// never as a decode failure. The wire rule in `ControlWireTests`.
    @Test func statsWithoutWakeStillDecode() throws {
        let json = Data("""
        {"pid":1,"footprintBytes":1,"pollCount":0,"ptyBytesIn":0,\
        "ptyBytesPerSecond":0,"uptimeSeconds":1}
        """.utf8)
        let decoded = try JSONDecoder().decode(StatsInfo.self, from: json)
        #expect(decoded.wake == nil)
    }
}
