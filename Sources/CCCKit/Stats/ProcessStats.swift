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
