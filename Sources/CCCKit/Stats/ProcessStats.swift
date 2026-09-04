import Darwin
import Foundation

/// How we're doing (scry's `ProcessStats`): phys_footprint is the number
/// Activity Monitor calls "Memory". Poll latency and PTY throughput are
/// supplied by their owners; this file only knows processes.
public enum ProcessStats {
    /// phys_footprint of a pid, nil if it is gone or not ours to inspect.
    public static func footprint(of pid: pid_t) -> UInt64? {
        var info = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
            }
        }
        guard result == 0 else { return nil }
        return info.ri_phys_footprint
    }

    /// How long a pid has been alive, nil if it is gone or not ours.
    ///
    /// From the kernel's own `ri_proc_start_abstime` rather than a `Date`
    /// taken at init, because the thing that wants it is the app's line of
    /// `ccc stats` and the app has several possible starts to choose from.
    /// Until 2026-09-03 that line printed the *attached pane's* age next to
    /// the app's `pid` and `memory` — and `0s` whenever nothing was
    /// attached, so a week-old app read "uptime 0s" the moment you detached.
    /// A number the process cannot be wrong about is the fix for a number
    /// that was being sourced from the wrong object.
    public static func uptime(of pid: pid_t) -> TimeInterval? {
        var info = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
            }
        }
        guard result == 0, info.ri_proc_start_abstime > 0 else { return nil }
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom > 0 else { return nil }
        let elapsed = mach_absolute_time() &- info.ri_proc_start_abstime
        let nanoseconds = Double(elapsed) * Double(timebase.numer) / Double(timebase.denom)
        return nanoseconds / 1_000_000_000
    }
}

/// Bytes-per-second over a sliding one-second window, for the PTY feed.
public struct Throughput: Sendable {
    public private(set) var total: UInt64 = 0
    private var window: [(at: ContinuousClock.Instant, bytes: Int)] = []

    public init() {}

    public mutating func record(_ bytes: Int) {
        total += UInt64(bytes)
        let now = ContinuousClock.now
        window.append((now, bytes))
        trim(now)
    }

    public mutating func bytesPerSecond() -> Double {
        trim(.now)
        return Double(window.reduce(0) { $0 + $1.bytes })
    }

    private mutating func trim(_ now: ContinuousClock.Instant) {
        window.removeAll { now - $0.at > .seconds(1) }
    }
}
