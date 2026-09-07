import Foundation
import Testing

@testable import CCCKit

/// Item 23: the ignored files a worktree needs anyway.
///
/// The harness copies what `.worktreeinclude` names into the worktrees *it*
/// cuts. Since v0.1.25 ccc cuts some itself (`--base`, or `--worktree` from
/// a folder off the default branch), and those got the tree without the
/// secrets. Measured 2026-09-06 across cuanto's 22 worktrees, whose
/// `.worktreeinclude` names `api/config/master.key`: **all 3 that ccc cut
/// lacked it, 16 of the 19 others had it** — and nothing anywhere said so,
/// so it surfaced as a worker whose API would not boot.
@Suite(.serialized) struct WorktreeIncludeTests {
    private struct Repo {
        let root: URL
        func git(_ line: String) throws -> String {
            try Git.run(WorktreeProbe.defaultGit, ["-C", root.path] + line.split(separator: " ").map(String.init))
                .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func write(_ path: String, _ text: String) throws {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// cuanto's shape in miniature: a `.gitignore` that hides `.env`,
    /// `node_modules/` and `config/master.key`, and a `.worktreeinclude`
    /// that asks for two of them back.
    private func withRepo(_ body: (Repo) throws -> Void) throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-wti-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = Repo(root: root)
        _ = try repo.git("init -q -b master")
        _ = try repo.git("config user.email t@example.com")
        _ = try repo.git("config user.name t")
        try repo.write(".gitignore", ".env\nnode_modules/\nconfig/master.key\nbuild/\n")
        try repo.write(".worktreeinclude", ".env\nconfig/master.key\n")
        try repo.write("a.txt", "one\n")
        _ = try repo.git("add .gitignore .worktreeinclude a.txt")
        _ = try repo.git("commit -q --no-verify -m first")
        // The ignored files themselves, never committed.
        try repo.write(".env", "SECRET=1\n")
        try repo.write("config/master.key", "deadbeef\n")
        try repo.write("apps/web/.env", "SECRET=2\n")
        // The trap: a bare `.env` pattern matches inside node_modules too,
        // and the harness does not copy that one.
        try repo.write("node_modules/psl/.env", "VENDORED=1\n")
        try repo.write("build/.env", "BUILT=1\n")
        try FileManager.default.createDirectory(at: root.appending(path: ".claude"), withIntermediateDirectories: true)
        try body(repo)
    }

    @Test func aWorktreeCccCutsCarriesWhatTheFileNames() throws {
        try withRepo { repo in
            let made = try WorktreeProbe.createWorktree(named: "w", base: "master", repo: repo.root.path)
            let worktree = URL(filePath: made.path)
            func has(_ path: String) -> Bool { FileManager.default.fileExists(atPath: worktree.appending(path: path).path) }

            #expect(has(".env"), "the file the whole feature exists for")
            #expect(has("config/master.key"), "and the one cuanto's ccc-cut worktrees were missing")
            #expect(has("apps/web/.env"), "an unanchored pattern matches at every depth, as gitignore says")
            #expect(made.carried.sorted() == [".env", "apps/web/.env", "config/master.key"])

            // Not from inside a directory git itself ignores. Measured on
            // cuanto: the harness copied ts-monorepo/apps/slackbot/.env and
            // not …/node_modules/psl/.env, and reading git's own list of
            // collapsed ignored directories is what makes that general
            // rather than a hardcoded "node_modules".
            #expect(!has("node_modules/psl/.env"))
            #expect(!has("build/.env"))
            #expect(!made.carried.contains { $0.contains("node_modules") })

            // The content, not just the name — a copy that made an empty
            // file would pass every check above.
            let secret = try String(contentsOf: worktree.appending(path: "config/master.key"), encoding: .utf8)
            #expect(secret == "deadbeef\n")
            // And the base is still recorded: carrying files is an addition
            // to the cut, never a replacement for it.
            #expect(made.base == "master" && made.branch == "worktree-w")
        }
    }

    /// Most repositories have no `.worktreeinclude` — ccc's own does not —
    /// and the cut must be exactly what it was before.
    @Test func noManifestCarriesNothingAndFailsNothing() throws {
        try withRepo { repo in
            try FileManager.default.removeItem(at: repo.root.appending(path: ".worktreeinclude"))
            let made = try WorktreeProbe.createWorktree(named: "bare", base: "master", repo: repo.root.path)
            #expect(made.carried.isEmpty)
            #expect(FileManager.default.fileExists(atPath: made.path + "/a.txt"))
            #expect(!FileManager.default.fileExists(atPath: made.path + "/.env"))
        }
    }

    /// A manifest naming files that do not exist is not an error: it is a
    /// repository where nobody has made a `.env` yet, which is normal.
    @Test func aManifestNamingNothingPresentIsQuiet() throws {
        try withRepo { repo in
            for path in [".env", "config/master.key", "apps/web/.env"] {
                try FileManager.default.removeItem(at: repo.root.appending(path: path))
            }
            let made = try WorktreeProbe.createWorktree(named: "empty", base: "master", repo: repo.root.path)
            #expect(made.carried.isEmpty)
        }
    }

    /// The answer names what it carried, because a secret that silently did
    /// or did not arrive is the whole defect.
    @Test func theSpawnAnswerSaysHowManyCameWith() {
        let made = SpawnResult.MadeWorktree(path: "/x", branch: "worktree-w", base: "storefront",
                                            carried: [".env", "api/config/master.key"])
        let result = SpawnResult(ref: SessionRef(id: "a1b2c3d4"), draft: false, cwd: "/x", said: "", worktree: made)
        #expect(result.description == "spawned a1b2c3d4 in worktree-w off storefront (+2 from .worktreeinclude)")
        let bare = SpawnResult(ref: SessionRef(id: "a1b2c3d4"), draft: false, cwd: "/x", said: "",
                               worktree: SpawnResult.MadeWorktree(path: "/x", branch: "worktree-w", base: "storefront"))
        #expect(bare.description == "spawned a1b2c3d4 in worktree-w off storefront")
    }

    /// It crosses the hop like every other field ccc adds, and an older ccc
    /// that sends no `carried` costs the row nothing.
    @Test func carriedSurvivesTheWireAndItsAbsence() throws {
        let made = SpawnResult.MadeWorktree(path: "/x", branch: "b", base: "m", carried: [".env"])
        let back = try JSONDecoder().decode(SpawnResult.MadeWorktree.self, from: JSONEncoder().encode(made))
        #expect(back == made)
        let old = Data(#"{"path":"/x","branch":"b","base":"m"}"#.utf8)
        #expect(try JSONDecoder().decode(SpawnResult.MadeWorktree.self, from: old).carried.isEmpty)
    }
}
