import Foundation
import Testing

@testable import CCCKit

/// The ssh prefix exists in exactly one function. These pin its shape, so
/// what the poll runs, what the PTY execs, and what the roster offers to
/// copy cannot drift apart — and so the two facts experiment 3 cost us
/// (absolute remote path, `-t` for attach) stay bought.
@Suite struct ClaudeCLIArgvTests {
    private let local = ClaudeCLI(executable: "/Users/x/.local/bin/claude")
    private let remote = ClaudeCLI(executable: "~/.local/bin/claude",
                                   host: Host(name: "studio", ssh: "studio", claude: "~/.local/bin/claude"))

    @Test func localIsTheCommandItself() {
        #expect(local.attachArgv(id: "a1b2") == ["/Users/x/.local/bin/claude", "attach", "a1b2"])
        #expect(local.agentsArgv() == ["/Users/x/.local/bin/claude", "agents", "--json", "--all"])
    }

    @Test func remoteAttachIsTheSameWordsBehindSSH() {
        let argv = remote.attachArgv(id: "a1b2")
        #expect(argv.first == "/usr/bin/ssh")
        // Absolute: the PTY execs argv[0] with execvp, and a GUI app has no
        // useful PATH.
        #expect(argv.contains("-t"), "attach needs a tty on the far side")
        #expect(argv.suffix(4) == ["studio", "~/.local/bin/claude", "attach", "a1b2"])
        // Unexpanded on purpose: `~` is the remote login shell's to expand.
        #expect(!argv.contains { $0.hasPrefix("/Users") })
    }

    /// The poll must not ask for a tty: `claude agents --json` would then
    /// negotiate a terminal and stop being a clean pipe to decode.
    @Test func remotePollAsksForNoTTY() {
        let argv = remote.agentsArgv()
        #expect(!argv.contains("-t"))
        #expect(argv.suffix(4) == ["~/.local/bin/claude", "agents", "--json", "--all"])
    }

    /// One multiplexed connection per host (CLAUDE.md): both the poll and
    /// the attach must name the same master socket, or every 2 s tick pays
    /// its own handshake.
    @Test func pollAndAttachShareOneMasterSocket() {
        let socket = remote.sshControlPath
        #expect(remote.agentsArgv().contains(socket.withControlPathPrefix))
        #expect(remote.attachArgv(id: "a1b2").contains(socket.withControlPathPrefix))
        #expect(socket.hasSuffix("/studio.sock"))
        // sockaddr_un caps a unix socket path near 104 bytes, which is why
        // the name in it is the host's, not the ssh destination's.
        #expect(socket.utf8.count < 104)
    }

    @Test func remotePollFailsFastRatherThanHangingATick() {
        #expect(remote.agentsArgv().contains("ConnectTimeout=5"))
        // No password prompt may ever block a background poll.
        #expect(remote.agentsArgv().contains("BatchMode=yes"))
    }

    @Test func theCopyableLineIsTheCommandWeRun() {
        #expect(local.attachCommandLine(id: "a1b2") == "/Users/x/.local/bin/claude attach a1b2")
        let line = remote.attachCommandLine(id: "a1b2")
        #expect(line.hasPrefix("/usr/bin/ssh -t "))
        #expect(line.hasSuffix("studio ~/.local/bin/claude attach a1b2"))
    }

    @Test func aHostWithoutAClaudePathHasNoCLI() {
        #expect(ClaudeCLI.of(Host(name: "air", ssh: "air")) == nil)
    }
}

private extension String {
    /// ssh takes the socket as `ControlPath=<path>` in one argv element.
    var withControlPathPrefix: String { "ControlPath=\(self)" }
}
