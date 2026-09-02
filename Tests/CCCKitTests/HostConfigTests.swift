import Foundation
import Testing

@testable import CCCKit

/// The host list is hand-editable, which means it will be hand-broken. The
/// rule is the roster's, turned on our own file: degrade to "local only"
/// with the reason shown, never an empty list and never a crash.
@Suite struct HostConfigTests {
    private func withTempConfig(_ json: String?, _ body: (String) throws -> Void) throws {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-hosts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appending(path: "hosts.json").path
        if let json { try Data(json.utf8).write(to: URL(filePath: path)) }
        try body(path)
    }

    @Test func noFileMeansThisMacAlone() throws {
        try withTempConfig(nil) { path in
            let loaded = HostConfig.load(path: path)
            #expect(loaded.config.hosts == [.local])
            #expect(loaded.issues.isEmpty)
        }
    }

    @Test func localIsAddedBackWhenTheFileForgetsIt() throws {
        try withTempConfig(#"{"hosts":[{"name":"studio","ssh":"studio","claude":"~/.local/bin/claude"}]}"#) { path in
            let loaded = HostConfig.load(path: path)
            #expect(loaded.config.hosts.map(\.name) == ["local", "studio"])
            #expect(loaded.config.host(named: "studio")?.ssh == "studio")
        }
    }

    /// A broken file must not take the roster down with it: the sessions on
    /// this Mac are still there to attach to.
    @Test func brokenJSONFallsBackToLocalWithTheReason() throws {
        try withTempConfig("{ this is not json") { path in
            let loaded = HostConfig.load(path: path)
            #expect(loaded.config.hosts == [.local])
            #expect(loaded.issues.count == 1)
            #expect(loaded.issues[0].contains("using local only"))
        }
    }

    @Test func anUnusableHostIsDroppedAndSaidSo() throws {
        try withTempConfig(#"{"hosts":[{"name":"air","ssh":"air"}]}"#) { path in
            let loaded = HostConfig.load(path: path)
            #expect(loaded.config.hosts == [.local])
            // Experiment 3's finding is the sentence the user sees.
            #expect(loaded.issues.first?.contains("no claude on PATH") == true)
        }
    }

    @Test func duplicatesKeepTheFirst() throws {
        let json = #"{"hosts":[{"name":"studio","ssh":"one","claude":"/c"},{"name":"studio","ssh":"two","claude":"/c"}]}"#
        try withTempConfig(json) { path in
            let loaded = HostConfig.load(path: path)
            #expect(loaded.config.host(named: "studio")?.ssh == "one")
            #expect(loaded.issues.first?.contains("duplicate") == true)
        }
    }

    @Test func saveThenLoadRoundTrips() throws {
        try withTempConfig(nil) { path in
            let config = HostConfig(hosts: [.local, Host(name: "studio", ssh: "studio.tailnet", claude: "~/.local/bin/claude")])
            try config.save(path: path)
            #expect(HostConfig.load(path: path).config == config)
        }
    }

    // MARK: validation

    @Test func aColonInAHostNameIsRefused() {
        // It would make `studio:a1b2` ambiguous, which is why the parser can
        // treat a single colon as the separator at all.
        #expect(Host(name: "a:b", ssh: "x", claude: "/c").validate()?.contains("':'") == true)
    }

    @Test func aClaudePathNeedingQuotesIsRefused() {
        // ccc hands the remote words to ssh unquoted so `~` expands; a path
        // with a space would silently split into two arguments there.
        let host = Host(name: "studio", ssh: "studio", claude: "/opt/my claude/bin/claude")
        #expect(host.validate()?.contains("unquoted") == true)
    }

    @Test func localNeedsNoClaudePath() {
        #expect(Host.local.validate() == nil)
    }
}
