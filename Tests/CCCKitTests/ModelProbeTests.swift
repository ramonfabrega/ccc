import CCCKit
import Foundation
import Testing

@Suite struct ModelProbeTests {
    // MARK: - Helpers

    /// A scratch directory in the system temp area; nothing here writes under
    /// `~/.claude`.
    private static func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ccc-modelprobe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func assistantLine(model: String, timestamp: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","model":"\#(model)","#
            + #""content":[{"type":"text","text":"x"}]},"timestamp":"\#(timestamp)"}"#
    }

    private static func iso(_ string: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: string)!
    }

    // MARK: - Fixture

    /// The fixture's tail is, newest-first: a user line, an attachment, a
    /// line that is not JSON at all, a system line, a `<synthetic>` assistant
    /// — all skipped — then the real answer. It also ends without a trailing
    /// newline, which the tail reader must not lose.
    @Test func fixtureTailFindsNewestRealModel() {
        let result = ModelProbe().model(forTranscriptAt: Fixtures.url("transcript/tail.jsonl"))
        #expect(result?.model == "claude-fable-5-1")
        #expect(result?.at == Self.iso("2026-09-02T01:05:00.000Z"))
    }

    @Test func lastLineWithoutTrailingNewlineIsStillScanned() throws {
        // Prove the final line is seen at all: make it the assistant record.
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "last.jsonl")
        let text = #"{"type":"user","message":{"role":"user","content":"hi"}}"# + "\n"
            + Self.assistantLine(model: "claude-haiku-9", timestamp: "2026-09-02T02:00:00.000Z")
        try text.write(to: url, atomically: true, encoding: .utf8)
        #expect(ModelProbe().model(forTranscriptAt: url)?.model == "claude-haiku-9")
    }

    @Test func syntheticModelsAreSkipped() throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "synthetic.jsonl")
        let text = [
            Self.assistantLine(model: "claude-opus-5", timestamp: "2026-09-02T01:00:00.000Z"),
            #"{"type":"user","message":{"role":"user","content":"stop"}}"#,
            Self.assistantLine(model: "<synthetic>", timestamp: "2026-09-02T01:01:00.000Z"),
            Self.assistantLine(model: "<synthetic>", timestamp: "2026-09-02T01:02:00.000Z"),
        ].joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)

        let result = ModelProbe().model(forTranscriptAt: url)
        #expect(result?.model == "claude-opus-5")
        #expect(result?.at == Self.iso("2026-09-02T01:00:00.000Z"))
    }

    @Test func invalidJSONLinesAreSkippedNotFatal() throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "garbage.jsonl")
        let text = [
            Self.assistantLine(model: "claude-opus-5", timestamp: "2026-09-02T01:00:00.000Z"),
            "{ this is not json",
            "",
            "[]",
            #"{"type":"assistant","message":{"role":"assistant","model":42}}"#,
        ].joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
        #expect(ModelProbe().model(forTranscriptAt: url)?.model == "claude-opus-5")
    }

    @Test func recordWithoutTimestampHasNilDate() throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "nots.jsonl")
        try #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-5"}}"#
            .write(to: url, atomically: true, encoding: .utf8)
        let result = ModelProbe().model(forTranscriptAt: url)
        #expect(result?.model == "claude-opus-5")
        #expect(result?.at == nil)
    }

    // MARK: - Failure modes

    @Test func missingFileIsNil() {
        let url = URL(filePath: "/tmp/ccc-does-not-exist-\(UUID().uuidString).jsonl")
        #expect(ModelProbe().model(forTranscriptAt: url) == nil)
    }

    @Test func emptyFileIsNil() throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "empty.jsonl")
        try Data().write(to: url)
        #expect(ModelProbe().model(forTranscriptAt: url) == nil)
    }

    @Test func noAssistantRecordIsNil() throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "none.jsonl")
        try (String(repeating: #"{"type":"user","message":{"role":"user","content":"x"}}"# + "\n",
                    count: 50))
            .write(to: url, atomically: true, encoding: .utf8)
        #expect(ModelProbe().model(forTranscriptAt: url) == nil)
    }

    // MARK: - Tail window

    /// Padding lines that are valid JSONL but never a match, sized so the
    /// generated files land where the test wants them.
    private static func padding(bytes: Int) -> String {
        let line = #"{"type":"user","message":{"role":"user","content":"#
            + "\"" + String(repeating: "p", count: 200) + "\"}}\n"
        let count = max(1, bytes / line.utf8.count)
        return String(repeating: line, count: count)
    }

    @Test func assistantBeyondTheFourMebibyteCapIsNotFound() throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "huge-head.jsonl")
        let text = Self.assistantLine(model: "claude-opus-5", timestamp: "2026-09-02T01:00:00.000Z")
            + "\n" + Self.padding(bytes: 5 * 1024 * 1024)
        try text.write(to: url, atomically: true, encoding: .utf8)

        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size > 5 * 1024 * 1024)
        #expect(ModelProbe().model(forTranscriptAt: url) == nil)
    }

    @Test func assistantThreeMebibytesFromTheEndIsFoundByDoubling() throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "huge-tail.jsonl")
        let text = Self.padding(bytes: 2 * 1024 * 1024)
            + Self.assistantLine(model: "claude-fable-5-1", timestamp: "2026-09-02T03:00:00.000Z")
            + "\n" + Self.padding(bytes: 3 * 1024 * 1024)
        try text.write(to: url, atomically: true, encoding: .utf8)

        let result = ModelProbe().model(forTranscriptAt: url)
        #expect(result?.model == "claude-fable-5-1")
        #expect(result?.at == Self.iso("2026-09-02T03:00:00.000Z"))
    }

    // MARK: - Cache

    @Test func cacheReturnsSameAnswerThenSeesAnAppend() throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "cached.jsonl")
        try (Self.assistantLine(model: "claude-opus-5", timestamp: "2026-09-02T01:00:00.000Z") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)

        let probe = ModelProbe()
        let first = probe.model(forTranscriptAt: url)
        #expect(first?.model == "claude-opus-5")
        #expect(probe.model(forTranscriptAt: url) == first)

        // Append a newer assistant record: size and mtime both move, so the
        // cache must miss.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(
            (Self.assistantLine(model: "claude-fable-5-1", timestamp: "2026-09-02T04:00:00.000Z")
             + "\n").utf8))
        try handle.close()

        let second = probe.model(forTranscriptAt: url)
        #expect(second?.model == "claude-fable-5-1")
        #expect(second?.at == Self.iso("2026-09-02T04:00:00.000Z"))
    }

    @Test func cacheIsPerPath() throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appending(path: "a.jsonl")
        let b = dir.appending(path: "b.jsonl")
        try (Self.assistantLine(model: "claude-opus-5", timestamp: "2026-09-02T01:00:00.000Z") + "\n")
            .write(to: a, atomically: true, encoding: .utf8)
        try (Self.assistantLine(model: "claude-haiku-9", timestamp: "2026-09-02T01:00:00.000Z") + "\n")
            .write(to: b, atomically: true, encoding: .utf8)

        let probe = ModelProbe()
        #expect(probe.model(forTranscriptAt: a)?.model == "claude-opus-5")
        #expect(probe.model(forTranscriptAt: b)?.model == "claude-haiku-9")
        #expect(probe.model(forTranscriptAt: a)?.model == "claude-opus-5")
    }
}
