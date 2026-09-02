import CCCKit
import Foundation
import Testing

@Suite struct WellPathTests {
    private static let home = URL(filePath: "/Users/rf-studio/.claude")

    @Test func mangleReplacesSlashesAndDots() {
        // Observed on disk 2026-09-02.
        #expect(
            WellPath.directory(
                forCwd: "/Users/rf-studio/code/fun/ccc/.claude/worktrees/v0",
                claudeHome: Self.home
            ).path(percentEncoded: false)
            == "/Users/rf-studio/.claude/projects/-Users-rf-studio-code-fun-ccc--claude-worktrees-v0")

        #expect(
            WellPath.directory(forCwd: "/Users/rf-studio/code/fun/lore", claudeHome: Self.home)
                .lastPathComponent == "-Users-rf-studio-code-fun-lore")

        // A dotted name mangles like any other dot.
        #expect(
            WellPath.directory(forCwd: "/tmp/babyhouse.club", claudeHome: Self.home)
                .lastPathComponent == "-tmp-babyhouse-club")
    }

    @Test func transcriptComposesSessionJSONL() {
        let url = WellPath.transcript(
            sessionId: "57084123-50ff-46c8-9e1b-431ac517df70",
            cwd: "/Users/rf-studio/code/fun/ccc/.claude/worktrees/v0",
            claudeHome: Self.home)
        #expect(url.path(percentEncoded: false)
            == "/Users/rf-studio/.claude/projects/-Users-rf-studio-code-fun-ccc--claude-worktrees-v0"
             + "/57084123-50ff-46c8-9e1b-431ac517df70.jsonl")
        #expect(url.pathExtension == "jsonl")
        // The transcript sits directly in the well directory.
        #expect(url.deletingLastPathComponent().lastPathComponent
            == WellPath.directory(
                forCwd: "/Users/rf-studio/code/fun/ccc/.claude/worktrees/v0", claudeHome: Self.home)
                .lastPathComponent)
    }

    /// Unverified territory, pinned so a future widening of the rule is a
    /// deliberate change: no cwd on this machine contains `_` or a space, so
    /// we leave them alone rather than guess.
    @Test func otherPunctuationIsLeftAlone() {
        #expect(
            WellPath.directory(forCwd: "/tmp/my_project dir", claudeHome: Self.home)
                .lastPathComponent == "-tmp-my_project dir")
    }
}
