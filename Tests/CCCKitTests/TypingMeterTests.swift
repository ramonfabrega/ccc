import Foundation
import Testing

@testable import CCCKit

/// `TypingMeter`: a keystroke in three parts, and what does not count as one.
@Suite struct TypingMeterTests {
    @Test func aKeystrokeIsTimedInThreeParts() {
        var meter = TypingMeter()
        meter.handled(lag: 0.002)
        meter.wrote(bytes: 1, at: 10.000)
        meter.read(at: 10.020)
        meter.presented(at: 10.026)
        #expect(meter.stats.input.recentMs == [2])
        #expect(meter.stats.echo.recentMs.map { ($0 * 10).rounded() / 10 } == [20])
        #expect(meter.stats.draw.recentMs.map { ($0 * 10).rounded() / 10 } == [6])
    }

    /// Two keys before one answer are one echo, timed from the first; and
    /// two reads before one frame are one draw, timed from the first.
    @Test func theFirstUnansweredEventIsTheOneTimed() {
        var meter = TypingMeter()
        meter.wrote(bytes: 1, at: 1.000)
        meter.wrote(bytes: 1, at: 1.010)
        meter.read(at: 1.030)
        meter.read(at: 1.032)
        meter.presented(at: 1.040)
        #expect(meter.stats.echo.count == 1)
        #expect(meter.stats.echo.recentMs.map { $0.rounded() } == [30])
        #expect(meter.stats.draw.count == 1)
        #expect(meter.stats.draw.recentMs.map { $0.rounded() } == [10])
    }

    /// A paste is not typing, an answer two seconds late is not an answer,
    /// and output nobody typed for has no echo — but is still drawn.
    @Test func whatIsNotAKeystrokeIsNotCounted() {
        var meter = TypingMeter()
        meter.wrote(bytes: 400, at: 1.0)
        meter.read(at: 1.1)
        #expect(meter.stats.echo.count == 0)

        meter.wrote(bytes: 1, at: 2.0)
        meter.read(at: 4.5)
        #expect(meter.stats.echo.count == 0)

        meter.presented(at: 4.51)
        #expect(meter.stats.draw.count == 1)
        meter.presented(at: 4.60)
        #expect(meter.stats.draw.count == 1, "a frame with no new bytes behind it is not a draw of anything")

        meter.handled(lag: -1)
        meter.handled(lag: 60)
        #expect(meter.stats.input.count == 0)
    }

    @Test func aLatencyKeepsItsLastWindowAndSaysMedianAndWorst() {
        var latency = Latency()
        for ms in 1...100 { latency.record(Double(ms)) }
        #expect(latency.count == 100)
        #expect(latency.recentMs.count == Latency.window)
        #expect(latency.recentMs.first == 37)
        #expect(latency.worstMs == 100)
        #expect(latency.medianMs == 69)
        #expect(Latency().medianMs == nil)
    }
}
