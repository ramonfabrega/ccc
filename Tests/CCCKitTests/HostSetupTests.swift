import Foundation
import Testing

@testable import CCCKit

/// `HostSetup.add` is the one definition behind two surfaces —
/// `ccc hosts add` and the app's picker (queue item 3). The reason it exists
/// is that the picker was about to be a second implementation of "what a
/// host needs", and the two would have drifted the first time one of them
/// learned something.
///
/// These pin the parts that do not need a reachable Mac: the refusals, and
/// what gets written. The reachable path is `ccc hosts check`, measured live
/// in docs/EVIDENCE.md ("v9 slice 6" registered the loopback at 648 ms).
@Suite struct HostSetupTests {
    private func tempPath() -> String {
        FileManager.default.temporaryDirectory
            .appending(path: "ccc-hosts-\(UUID().uuidString).json").path
    }

    /// A name that could not survive `hosts.json` is refused before any ssh
    /// is attempted, and nothing is written. `:` is what separates host from
    /// id in `ccc attach host:id`.
    @Test func anUnusableNameIsRefusedAndNothingIsWritten() async throws {
        let path = tempPath()
        let result = await HostSetup.add(name: "a:b", claude: "/usr/bin/claude", into: path)
        guard case .failure(let problem) = result else {
            Issue.record("expected a refusal, got \(result)")
            return
        }
        guard case .invalid = problem else {
            Issue.record("expected .invalid, got \(problem)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: path) == false)
    }

    /// Experiment 3's lesson, enforced: a remote host with no claude path is
    /// not saved, because a non-interactive ssh has no claude on PATH and the
    /// roster would look like an outage rather than a misconfiguration.
    @Test func aHostWithNoClaudeIsRefused() async throws {
        let path = tempPath()
        // A destination that cannot resolve, so the probe fails rather than
        // reaching anything real. The refusal is what is being pinned.
        let result = await HostSetup.add(
            name: "nowhere", ssh: "ccc-test-invalid.invalid", into: path)
        guard case .failure(let problem) = result else {
            Issue.record("expected a refusal, got \(result)")
            return
        }
        // Either shape is correct here — what matters is that it refused and
        // wrote nothing. Which one depends on how the resolver fails.
        switch problem {
        case .noClaude, .unknownHostKey: break
        default: Issue.record("expected noClaude or unknownHostKey, got \(problem)")
        }
        #expect(FileManager.default.fileExists(atPath: path) == false)
    }

    /// An explicit `--claude` skips the probe's answer, which is what lets a
    /// host be added before it is reachable — and what the picker never uses,
    /// since it always has a live machine in front of it.
    @Test func anExplicitClaudePathIsSavedWithoutTheProbe() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let result = await HostSetup.add(
            name: "elsewhere", ssh: "ccc-test-invalid.invalid",
            claude: "~/.local/bin/claude", into: path)
        guard case .success(let added) = result else {
            Issue.record("expected a save, got \(result)")
            return
        }
        #expect(added.host.name == "elsewhere")
        #expect(added.host.claude == "~/.local/bin/claude")
        #expect(added.host.ccc == nil)
        // The unreachable probe is a note, not a failure: the host is usable
        // the moment the far side answers.
        #expect(added.notes.contains { $0.contains("could not reach") })

        // `local` is always present — a load injects this Mac — so the
        // question is what was appended, not what the list equals.
        let reloaded = HostConfig.load(path: path).config
        #expect(reloaded.hosts.map(\.name) == ["local", "elsewhere"])
    }

    /// `ssh` defaults to the name, which is the **short MagicDNS label** —
    /// `known_hosts` and `~/.ssh/config` are keyed on what a human types, so
    /// `studio` works where `studio.bengal-barb.ts.net` fails host key
    /// verification (docs/EVIDENCE.md "v9 slice 6"). The picker relies on
    /// this default rather than passing `dnsName`.
    @Test func sshDefaultsToTheName() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        _ = await HostSetup.add(name: "shortlabel", claude: "/usr/bin/claude", into: path)
        let saved = try #require(HostConfig.load(path: path).config.hosts.first { $0.name == "shortlabel" })
        #expect(saved.ssh == "shortlabel")
    }

    /// Adding the same name twice replaces rather than duplicates — two rows
    /// with one name is a roster that cannot be addressed.
    @Test func addingTwiceReplaces() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        _ = await HostSetup.add(name: "twice", claude: "/usr/bin/one", into: path)
        _ = await HostSetup.add(name: "twice", claude: "/usr/bin/two", into: path)
        let hosts = HostConfig.load(path: path).config.hosts.filter { $0.name == "twice" }
        #expect(hosts.count == 1)
        #expect(hosts.first?.claude == "/usr/bin/two")
    }

    /// `--no-ccc` is a choice, not a failure: the roster still works through
    /// `claude agents`, just without the model column (v2 slice 1).
    @Test func noCCCIsANoteNotARefusal() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let result = await HostSetup.add(
            name: "bare", ssh: "ccc-test-invalid.invalid",
            claude: "/usr/bin/claude", wantCCC: false, into: path)
        guard case .success(let added) = result else {
            Issue.record("expected a save, got \(result)")
            return
        }
        #expect(added.host.ccc == nil)
        #expect(added.notes.contains { $0.contains("no ccc on") } == false,
                "with --no-ccc, a missing ccc is the request, not a note")
    }
}
