import Foundation

/// The well directory for a cwd: `~/.claude/projects/<mangled cwd>`, where
/// the harness mangles `/` and `.` to `-` (observed on disk 2026-09-02:
/// `/Users/x/code/fun/ccc/.claude/worktrees/v0` →
/// `-Users-x-code-fun-ccc--claude-worktrees-v0`). Read-only; ccc never
/// writes under `~/.claude`.
///
/// Evidence for other characters: all 107 directories in
/// `~/.claude/projects` on this machine match `[A-Za-z0-9-]+` only, and no
/// project cwd on this machine contains `_`, a space, or other punctuation
/// (checked 2026-09-02), so whether the harness also mangles those is
/// **unverified**. We mangle only `/` and `.` and leave everything else
/// alone; when a path with `_` or a space shows up, compare against the
/// directory the harness actually creates before widening the rule.
public enum WellPath {
    public static func directory(forCwd cwd: String, claudeHome: URL = defaultClaudeHome) -> URL {
        var mangled = ""
        mangled.reserveCapacity(cwd.count)
        for character in cwd {
            mangled.append(character == "/" || character == "." ? "-" : character)
        }
        return claudeHome.appending(path: "projects").appending(path: mangled)
    }

    public static func transcript(sessionId: String, cwd: String, claudeHome: URL = defaultClaudeHome) -> URL {
        directory(forCwd: cwd, claudeHome: claudeHome).appending(path: "\(sessionId).jsonl")
    }

    /// The transcript a session actually has. The roster's `cwd` is where
    /// the session runs now; the transcript follows the well the harness
    /// chose, and worktree isolation moves it (lore's re-derived finding:
    /// entering a worktree mid-session relocates the whole file to the
    /// worktree's well). Tries the direct path, then every well under
    /// `projects/` — one `stat` per well, ~100 on this machine.
    public static func locateTranscript(sessionId: String, cwd: String, claudeHome: URL = defaultClaudeHome) -> URL? {
        let direct = transcript(sessionId: sessionId, cwd: cwd, claudeHome: claudeHome)
        let fm = FileManager.default
        if fm.fileExists(atPath: direct.path) { return direct }
        let projects = claudeHome.appending(path: "projects")
        guard let wells = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else { return nil }
        for well in wells {
            let candidate = well.appending(path: "\(sessionId).jsonl")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    public static var defaultClaudeHome: URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !override.isEmpty {
            return URL(filePath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
    }
}

/// The model actually serving a session: the `message.model` of the last
/// `type: "assistant"` record in the transcript. Neither the roster nor
/// `state.json` carries a model (lore verified this); the transcript tail is
/// the only source, and it is what `lore agents` reads too.
///
/// Contract:
/// - Read from the end of the file, in chunks (start 64 KiB, double as
///   needed, cap at 4 MiB), never the whole file — transcripts run to
///   hundreds of MB.
/// - Scan lines newest-first; the first line that parses as JSON with
///   `type == "assistant"` and a string at `message.model` wins.
/// - Cache per path keyed on (size, mtime); a poll that sees the same
///   (size, mtime) returns the cached answer without opening the file.
/// - Missing file, unreadable file, or no assistant record → nil, never
///   an error. `<synthetic>` models are skipped.
public final class ModelProbe: @unchecked Sendable {
    public struct Result: Sendable, Equatable {
        public var model: String
        public var at: Date?   // the record's `timestamp`, when present
    }

    private struct Stamp: Equatable {
        var size: UInt64
        var mtime: Date
    }

    private struct Entry {
        var stamp: Stamp
        var result: Result?
    }

    private static let firstChunk = 64 * 1024
    private static let maxChunk = 4 * 1024 * 1024

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]

    public init() {}

    public func model(forTranscriptAt url: URL) -> Result? {
        guard let stamp = Self.stamp(of: url) else { return nil }
        let key = url.path(percentEncoded: false)

        lock.lock()
        if let cached = cache[key], cached.stamp == stamp {
            lock.unlock()
            return cached.result
        }
        lock.unlock()

        let result = Self.probe(url, size: stamp.size)

        lock.lock()
        cache[key] = Entry(stamp: stamp, result: result)
        lock.unlock()
        return result
    }

    // MARK: - Reading

    /// Deliberately `FileManager`, not `URL.resourceValues`: a `URL` instance
    /// caches its resource values, so a caller that polls the same `URL`
    /// would keep seeing the size and mtime from the first lookup and the
    /// cache below would never invalidate.
    private static func stamp(of url: URL) -> Stamp? {
        guard let attributes = try? FileManager.default
            .attributesOfItem(atPath: url.path(percentEncoded: false)),
            let size = attributes[.size] as? NSNumber,
            let mtime = attributes[.modificationDate] as? Date
        else { return nil }
        return Stamp(size: size.uint64Value, mtime: mtime)
    }

    /// Tail the file in doubling chunks, scanning newest-first, until an
    /// assistant record is found, the whole file has been read, or the 4 MiB
    /// cap is reached.
    private static func probe(_ url: URL, size: UInt64) -> Result? {
        guard size > 0, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var window = firstChunk
        while true {
            let capped = min(UInt64(window), size)
            let offset = size - capped
            guard let data = try? read(handle, from: offset, count: Int(capped)) else { return nil }

            // A chunk boundary can split a line; drop the first partial line
            // unless this window reaches the start of the file.
            var slice = data[...]
            if offset > 0, let newline = slice.firstIndex(of: UInt8(ascii: "\n")) {
                slice = slice[slice.index(after: newline)...]
            }
            if let found = scanNewestFirst(slice) { return found }

            if capped == size { return nil }               // read the whole file, nothing found
            if window >= maxChunk { return nil }           // cap respected
            window = min(window * 2, maxChunk)
        }
    }

    private static func read(_ handle: FileHandle, from offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: count) ?? Data()
    }

    private static func scanNewestFirst(_ bytes: Data.SubSequence) -> Result? {
        for line in bytes.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true).reversed() {
            if let result = parse(Data(line)) { return result }
        }
        return nil
    }

    /// One JSONL record → a result, or nil when it is not an assistant record
    /// with a usable model. Invalid JSON is skipped, never fatal.
    private static func parse(_ line: Data) -> Result? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let model = message["model"] as? String,
              !model.isEmpty,
              !model.contains("<synthetic>")
        else { return nil }

        var at: Date?
        if let timestamp = object["timestamp"] as? String {
            at = date(fromISO8601: timestamp)
        }
        return Result(model: model, at: at)
    }

    /// Transcript timestamps are ISO 8601 with fractional seconds
    /// (`2026-09-02T01:05:00.000Z`); accept the plain form too. Value-type
    /// format styles, so no shared mutable formatter.
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    private static func date(fromISO8601 string: String) -> Date? {
        (try? fractional.parse(string)) ?? (try? plain.parse(string))
    }
}
