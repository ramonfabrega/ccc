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
        #expect(local.spawnArgv(request) == ["/Users/x/.local/bin/claude", "--bg", "--name", "fix", "--model", "opus", "fix the failing test"])
        // The cwd is where the child runs, never a word: the harness has no --cwd.
        #expect(local.spawnCwd(request) == "/Users/x/code/app")
        #expect(!local.spawnArgv(request).contains("/Users/x/code/app"))
    }

    @Test func aDraftHasNoPromptWord() {
        let request = SpawnRequest(prompt: "  \n", name: "later")
        #expect(request.isDraft)
        #expect(local.spawnArgv(request) == ["/Users/x/.local/bin/claude", "--bg", "--name", "later"])
        #expect(local.spawnCwd(request) == nil)
    }

    @Test func everyFlagIsPassedThroughUnchanged() {
        let request = SpawnRequest(prompt: "go", agent: "lean", permissionMode: "auto", effort: "high", worktree: "v6")
        #expect(request.claudeArguments == ["--bg", "--agent", "lean", "--permission-mode", "auto", "--effort", "high", "--worktree", "v6", "go"])
        #expect(SpawnRequest(worktree: "").claudeArguments == ["--bg", "--worktree"])
        #expect(SpawnRequest(worktree: nil).claudeArguments == ["--bg"])
    }

    /// Remote: no tty, a `cd` on the far side, and the prompt one quoted
    /// word so ssh's join and the login shell's split cannot break it.
    @Test func remoteChangesDirectoryThereAndQuotesThePrompt() {
        let request = SpawnRequest(cwd: "~/code/app", prompt: "say it's done; then stop", name: "n")
        let argv = remote.spawnArgv(request)
        #expect(argv.first == "/usr/bin/ssh")
        #expect(!argv.contains("-t"))
        let tail = Array(argv.drop { $0 != "studio" }.dropFirst())
        #expect(tail == ["cd", "~/code/app", "&&", "~/.local/bin/claude", "--bg", "--name", "n", "'say it'\\''s done; then stop'"])
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
        #expect(argv.suffix(3) == ["~/.local/bin/claude", "--bg", "go"])
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
        #expect(local.spawnCommandLine(SpawnRequest(cwd: "/tmp/x", prompt: "go on")) == "cd /tmp/x && /Users/x/.local/bin/claude --bg 'go on'")
        #expect(remote.spawnCommandLine(SpawnRequest(cwd: "~/x", prompt: "go on")).hasSuffix("studio cd ~/x && ~/.local/bin/claude --bg 'go on'"))
    }
}
