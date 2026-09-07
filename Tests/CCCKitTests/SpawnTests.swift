import Foundation
import Testing

@testable import CCCKit

/// v5: `claude --bg` behind the same one prefix, and the harness's answer
/// parsed. The two recorded answers are byte-for-byte what 2.1.259 printed
/// on 2026-09-02 (`scripts/spawn-probe`), ANSI included, so a change in
/// the harness's wording fails here before it fails a user.
@Suite struct SpawnTests {
    private let local = ClaudeCLI(executable: "/Users/x/.local/bin/claude")
    private let remote = ClaudeCLI(executable: "~/.local/bin/claude",
                                   host: Host(name: "studio", ssh: "studio", claude: "~/.local/bin/claude", home: "/Users/rf-studio"))

    static let promptedAnswer = "backgrounded · \u{1B}[36m2f4c7814\u{1B}[39m · ccc-v5-probe\n\u{1B}[2m  claude agents             list sessions\u{1B}[22m\n\u{1B}[2m  claude attach 2f4c7814    open in this terminal\u{1B}[22m\n"
    static let draftAnswer = "backgrounded · \u{1B}[36m5fc5d4fb\u{1B}[39m · ccc-v5-draft\u{1B}[2m (idle — send a prompt to start)\u{1B}[22m\n\u{1B}[2m  claude agents             list sessions\u{1B}[22m\n"
    static let unnamedDraftAnswer = "backgrounded · \u{1B}[36m6b7e3fe6\u{1B}[39m\u{1B}[2m (idle — send a prompt to start)\u{1B}[22m\n"

    // MARK: the words

    @Test func localIsTheHarnessesWordsWithThePromptLast() {
        let request = SpawnRequest(cwd: "/Users/x/code/app", prompt: "fix the failing test", name: "fix", model: "opus")
        #expect(local.spawnArgv(request) == ["/Users/x/.local/bin/claude", "--bg", "--name", "fix", "--model", "opus", "--permission-mode", "auto", "fix the failing test"])
        // The cwd is where the child runs, never a word: the harness has no --cwd.
        #expect(local.spawnCwd(request) == "/Users/x/code/app")
        #expect(!local.spawnArgv(request).contains("/Users/x/code/app"))
    }

    // MARK: fork (slice 3)

    @Test func aForkResumesTheFullSessionIdAndForks() {
        let sid = "1e7c5066-32da-4862-acef-0fc6b39f1bf9"
        let request = SpawnRequest(cwd: "/Users/x/cc-test", prompt: "carry on", name: "twin", from: sid)
        #expect(request.isFork)
        #expect(request.claudeArguments == ["--bg", "--resume", sid, "--fork-session", "--name", "twin", "--permission-mode", "auto", "carry on"])
        // A forked draft: the transcript, no prompt (measured: it restores on the first one).
        let draft = SpawnRequest(from: sid)
        #expect(draft.isDraft && draft.isFork)
        #expect(draft.claudeArguments == ["--bg", "--resume", sid, "--fork-session", "--permission-mode", "auto"])
        // An empty `from` is no fork at all.
        #expect(!SpawnRequest(from: "").isFork)
        #expect(SpawnRequest(from: "").claudeArguments == ["--bg", "--permission-mode", "auto"])
    }

    @Test func aRemoteForkKeepsTheIdBareAcrossTheHop() {
        let sid = "1e7c5066-32da-4862-acef-0fc6b39f1bf9"
        let argv = remote.spawnArgv(SpawnRequest(cwd: "/Users/rf-studio/cc-test", prompt: "carry on", from: sid))
        let tail = Array(argv.drop { $0 != "studio" }.dropFirst())
        #expect(tail == ["cd", "/Users/rf-studio/cc-test", "&&", "~/.local/bin/claude", "--bg", "--resume", sid, "--fork-session", "--permission-mode", "auto", "'carry on'"])
    }

    @Test func theAnswerNamesTheLineage() {
        let ref = SessionRef(host: Host.localName, id: "092ff6ad")
        let sid = "1e7c5066-32da-4862-acef-0fc6b39f1bf9"
        #expect(SpawnResult(ref: ref, draft: false, cwd: nil, said: "", from: sid).description == "spawned 092ff6ad from 1e7c5066")
        #expect(SpawnResult(ref: ref, draft: true, cwd: nil, said: "", from: sid).description
                == "drafted 092ff6ad from 1e7c5066 (idle — attach and send a prompt)")
        #expect(SpawnResult(ref: ref, draft: false, cwd: nil, said: "").description == "spawned 092ff6ad")
        // Off the wire from an older ccc the field is simply absent.
        let decoded = try? JSONDecoder().decode(SpawnResult.self, from: Data(#"{"ref":"092ff6ad","draft":false,"said":""}"#.utf8))
        #expect(decoded?.from == nil)
    }

    @Test func aDraftHasNoPromptWord() {
        let request = SpawnRequest(prompt: "  \n", name: "later")
        #expect(request.isDraft)
        #expect(local.spawnArgv(request) == ["/Users/x/.local/bin/claude", "--bg", "--name", "later", "--permission-mode", "auto"])
        #expect(local.spawnCwd(request) == nil)
    }

    @Test func everyFlagIsPassedThroughUnchanged() {
        let request = SpawnRequest(prompt: "go", agent: "lean", permissionMode: "plan", effort: "high", worktree: "v6", rc: true)
        #expect(request.claudeArguments == ["--bg", "--agent", "lean", "--rc", "--worktree", "v6", "--permission-mode", "plan", "--effort", "high", "go"])
        #expect(SpawnRequest(worktree: "").claudeArguments == ["--bg", "--worktree", "--permission-mode", "auto"])
        #expect(SpawnRequest(worktree: nil).claudeArguments == ["--bg", "--permission-mode", "auto"])
    }

    /// `--remote-control [name]` and `-w, --worktree [name]` take an
    /// **optional** value, so a bare one standing last before the
    /// positional prompt eats it. Both shipped that way and both were
    /// measured 2026-09-07 (`docs/EVIDENCE.md` "item 17 — the roster says
    /// nothing about `--rc`"): `--rc` made a draft with `intent: ""` and
    /// no error at all, `--worktree` died `exit 1 before init` on an
    /// invalid worktree name that was the prompt.
    ///
    /// The invariant is structural rather than positional, so a flag added
    /// in the wrong place fails here and not on a user's spawn: no
    /// optional-value flag may be the last word before the prompt, in any
    /// combination of the flags that can precede it.
    @Test func anOptionalValueFlagNeverStandsBeforeThePrompt() {
        for rc in [nil, true] as [Bool?] {
            for worktree in [nil, "", "v6"] as [String?] {
                for effort in [nil, "high"] as [String?] {
                    for model in [nil, "haiku"] as [String?] {
                        let argv = SpawnRequest(prompt: "go", model: model, effort: effort,
                                                worktree: worktree, rc: rc).claudeArguments
                        #expect(argv.last == "go")
                        let beforePrompt = argv[argv.count - 2]
                        #expect(!SpawnRequest.optionalValueFlags.contains(beforePrompt),
                                "\(beforePrompt) would swallow the prompt: \(argv)")
                        // And the same for a draft, whose last word is a
                        // flag: a trailing bare `--rc`/`--worktree` is
                        // harmless there, but only because nothing follows.
                        let draft = SpawnRequest(model: model, effort: effort, worktree: worktree, rc: rc)
                        #expect(!draft.claudeArguments.contains("go"))
                    }
                }
            }
        }
    }

    /// The mode defaults to `auto` (2026-09-04, the user's word via lore):
    /// a worker answered from a phone cannot be un-prompted there. Any
    /// explicit mode wins — `default` included, since that is the
    /// harness's own name for the one that asks — and `--base` is never
    /// a harness word: it is ccc's, consumed before the argv is built.
    @Test func theModeDefaultsToAutoAndAnExplicitOneWins() {
        #expect(SpawnRequest(prompt: "go").claudeArguments == ["--bg", "--permission-mode", "auto", "go"])
        #expect(SpawnRequest(prompt: "go", permissionMode: "default").claudeArguments == ["--bg", "--permission-mode", "default", "go"])
        #expect(SpawnRequest(prompt: "go", permissionMode: "").effectivePermissionMode == "auto")
        #expect(!SpawnRequest(prompt: "go", base: "storefront").claudeArguments.contains("--base"))
        #expect(!SpawnRequest(prompt: "go", base: "storefront").claudeArguments.contains("storefront"))
    }

    /// The answer names the worktree ccc cut, and an older ccc's answer
    /// without one still decodes.
    @Test func theAnswerNamesTheCut() throws {
        let ref = SessionRef(host: Host.localName, id: "092ff6ad")
        let made = SpawnResult.MadeWorktree(path: "/x/.claude/worktrees/w", branch: "worktree-w", base: "storefront")
        #expect(SpawnResult(ref: ref, draft: false, cwd: "/x", said: "", worktree: made).description
                == "spawned 092ff6ad in worktree-w off storefront")
        let old = try JSONDecoder().decode(SpawnResult.self, from: Data(#"{"ref":"092ff6ad","draft":false,"said":""}"#.utf8))
        #expect(old.worktree == nil)
    }

    /// Remote: no tty, a `cd` on the far side, and the prompt one quoted
    /// word so ssh's join and the login shell's split cannot break it.
    @Test func remoteChangesDirectoryThereAndQuotesThePrompt() {
        let request = SpawnRequest(cwd: "~/code/app", prompt: "say it's done; then stop", name: "n")
        let argv = remote.spawnArgv(request)
        #expect(argv.first == "/usr/bin/ssh")
        #expect(!argv.contains("-t"))
        let tail = Array(argv.drop { $0 != "studio" }.dropFirst())
        #expect(tail == ["cd", "~/code/app", "&&", "~/.local/bin/claude", "--bg", "--name", "n", "--permission-mode", "auto", "'say it'\\''s done; then stop'"])
        #expect(remote.spawnCwd(request) == nil)
        #expect(argv.contains("-o") && argv.contains { $0.hasPrefix("ControlPath=") && $0.hasSuffix("/studio.sock") })
    }

    @Test func remoteWordsStayBareWhenAShellWouldPassThemThrough() {
        #expect(ClaudeCLI.remoteWord("~/code/app") == "~/code/app")
        #expect(ClaudeCLI.remoteWord("--model=opus") == "--model=opus")
        #expect(ClaudeCLI.remoteWord("two words") == "'two words'")
        #expect(ClaudeCLI.remoteWord("~/my dir") == "~/'my dir'")
        #expect(ClaudeCLI.remoteWord("$HOME") == "'$HOME'")
        #expect(ClaudeCLI.remoteWord("") == "''")
    }

    @Test func aRemoteRequestWithoutACwdHasNoCd() {
        let argv = remote.spawnArgv(SpawnRequest(prompt: "go"))
        #expect(!argv.contains("cd"))
        #expect(argv.suffix(5) == ["~/.local/bin/claude", "--bg", "--permission-mode", "auto", "go"])
    }

    // MARK: the answer

    @Test func theIdIsReadThroughTheColour() {
        let parsed = ClaudeCLI.parseSpawnAnswer(Self.promptedAnswer)
        #expect(parsed?.id == "2f4c7814")
        #expect(parsed?.draft == false)
    }

    @Test func theDraftIsNamedByTheHarnessesOwnParenthesis() {
        let named = ClaudeCLI.parseSpawnAnswer(Self.draftAnswer)
        #expect(named?.id == "5fc5d4fb")
        #expect(named?.draft == true)
        let unnamed = ClaudeCLI.parseSpawnAnswer(Self.unnamedDraftAnswer)
        #expect(unnamed?.id == "6b7e3fe6")
        #expect(unnamed?.draft == true)
    }

    @Test func anythingElseIsNotASpawn() {
        #expect(ClaudeCLI.parseSpawnAnswer("") == nil)
        #expect(ClaudeCLI.parseSpawnAnswer("Error: unknown option '--bg'") == nil)
        #expect(ClaudeCLI.parseSpawnAnswer("backgrounded · ") == nil)
        // A second line's hint must not be mistaken for the draft mark.
        let split = "backgrounded · \u{1B}[36mabcdef12\u{1B}[39m\n(idle — send a prompt to start)"
        #expect(ClaudeCLI.parseSpawnAnswer(split)?.draft == false)
    }

    @Test func ansiIsStrippedWhole() {
        #expect(ClaudeCLI.stripANSI("a\u{1B}[36mb\u{1B}[39mc\u{1B}[2K") == "abc")
        #expect(ClaudeCLI.stripANSI("plain") == "plain")
    }

    @Test func theResultReadsAsOneLine() {
        let ref = SessionRef(host: "studio", id: "5fc5d4fb")
        #expect(SpawnResult(ref: ref, draft: true, cwd: nil, said: "").description == "drafted studio:5fc5d4fb (idle — attach and send a prompt)")
        #expect(SpawnResult(ref: ref, draft: false, cwd: nil, said: "").description == "spawned studio:5fc5d4fb")
    }

    /// The pasteable line names the cwd locally (a `cd` a human would
    /// type) and carries it as a word remotely.
    @Test func theCommandLineIsWhatWouldRun() {
        #expect(local.spawnCommandLine(SpawnRequest(cwd: "/tmp/x", prompt: "go on")) == "cd /tmp/x && /Users/x/.local/bin/claude --bg --permission-mode auto 'go on'")
        #expect(remote.spawnCommandLine(SpawnRequest(cwd: "~/x", prompt: "go on")).hasSuffix("studio cd ~/x && ~/.local/bin/claude --bg --permission-mode auto 'go on'"))
    }
}
