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

    /// The probe lore minted to settle the rule: `_`, space, `~`, `+`, `@`
    /// all collapse to `-` (CLI 2.1.258; the well is still on disk as the
    /// evidence).
    @Test func everyNonAlphanumericCollapses() {
        #expect(
            WellPath.directory(forCwd: "/Users/rf-studio/cc-test/probe_a b/c~d+e@f", claudeHome: Self.home)
                .lastPathComponent == "-Users-rf-studio-cc-test-probe-a-b-c-d-e-f")
        #expect(
            WellPath.directory(forCwd: "/tmp/my_project dir", claudeHome: Self.home)
                .lastPathComponent == "-tmp-my-project-dir")
    }

    /// Probes 2 and 3: one dash per NFC character (not per byte), and an
    /// NFD path from a directory listing encodes like the NFC form the
    /// transcript records.
    @Test func nonASCIIIsPerCharacterAfterNFC() {
        #expect(
            WellPath.directory(forCwd: "/Users/rf-studio/cc-test/probé café ünïcode/日本語dir", claudeHome: Self.home)
                .lastPathComponent == "-Users-rf-studio-cc-test-prob--caf---n-code----dir")
        let nfd = "/Users/rf-studio/cc-test/cafe\u{0301}-nfd"      // e + combining acute, as APFS returns it
        let nfc = "/Users/rf-studio/cc-test/caf\u{00E9}-nfd"
        #expect(nfd.utf8.count == nfc.utf8.count + 1)   // Swift String == is canonical; the bytes differ
        #expect(WellPath.directory(forCwd: nfd, claudeHome: Self.home).lastPathComponent == "-Users-rf-studio-cc-test-caf--nfd")
        #expect(WellPath.directory(forCwd: nfc, claudeHome: Self.home).lastPathComponent == "-Users-rf-studio-cc-test-caf--nfd")
    }

    /// lore's corpus of real wells (`~/.claude/projects`, cwd taken from the
    /// transcript records, never reverse-derived). `strict` wells come from a
    /// session whose every record carries one cwd, so that cwd is the shard
    /// key exactly; the rest only promise that some observed cwd encodes to
    /// the well (sessions cd around, worktree relocation drags records).
    @Test func realWellCorpusEncodes() throws {
        struct Row: Decodable {
            var well: String
            var cwd: String
            var strict: Bool
            var cwds: [String]
        }
        let text = try String(contentsOf: Fixtures.url("wells/wells.jsonl"), encoding: .utf8)
        let lines = text.split(separator: "\n").dropFirst()   // line 1 is the header
        var strict = 0, loose = 0
        for line in lines {
            let row = try JSONDecoder().decode(Row.self, from: Data(line.utf8))
            func encode(_ cwd: String) -> String {
                WellPath.directory(forCwd: cwd, claudeHome: Self.home).lastPathComponent
            }
            if row.strict {
                #expect(encode(row.cwd) == row.well, "strict well \(row.well) from cwd \(row.cwd)")
                strict += 1
            } else {
                #expect(row.cwds.contains { encode($0) == row.well }, "no observed cwd encodes to \(row.well)")
                loose += 1
            }
        }
        #expect(strict == 45 && loose == 45, "corpus shape changed: \(strict) strict, \(loose) loose")
    }
}
