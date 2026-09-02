import Foundation

/// The well directory for a cwd: `~/.claude/projects/<mangled cwd>`, where
/// the harness mangles `/` and `.` to `-` (observed on disk 2026-09-02:
/// `/Users/x/code/fun/ccc/.claude/worktrees/v0` →
/// `-Users-x-code-fun-ccc--claude-worktrees-v0`). Read-only; ccc never
/// writes under `~/.claude`.
public enum WellPath {
    public static func directory(forCwd cwd: String, claudeHome: URL = defaultClaudeHome) -> URL {
        fatalError("TODO: WellPath.directory — spawn-owned")
    }

    public static func transcript(sessionId: String, cwd: String, claudeHome: URL = defaultClaudeHome) -> URL {
        directory(forCwd: cwd, claudeHome: claudeHome).appending(path: "\(sessionId).jsonl")
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

    public init() {}

    public func model(forTranscriptAt url: URL) -> Result? {
        fatalError("TODO: ModelProbe.model — spawn-owned")
    }
}
