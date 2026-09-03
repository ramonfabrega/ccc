import Foundation
import Testing

@testable import CCCKit

/// v3 slice 2: a per-host mute is a mark in hosts.json. What happened is
/// the detector's; what to say is the config's, and this is that split.
@Suite struct MuteTests {
    private func withTempConfig(_ json: String?, _ body: (String) throws -> Void) throws {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-mute-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appending(path: "hosts.json").path
        if let json { try Data(json.utf8).write(to: URL(filePath: path)) }
        try body(path)
    }

    private func event(_ host: String, _ id: String) -> SessionEvent {
        SessionEvent(kind: .blocked, ref: SessionRef(host: host, id: id), name: nil, at: Date(timeIntervalSince1970: 0))
    }

    /// The hand-edit: `"mute": true` on a host entry. An older file with
    /// no such key is unmuted everywhere, and the filter is then identity.
    @Test func theKeyIsReadFromTheFileAndAbsentMeansUnmuted() throws {
        try withTempConfig(#"""
        {"hosts":[{"name":"local"},
                  {"name":"air","ssh":"air","claude":"~/.local/bin/claude","mute":true},
                  {"name":"studio","ssh":"studio","claude":"~/.local/bin/claude","mute":false}]}
        """#) { path in
            let config = HostConfig.load(path: path).config
            #expect(config.mutedHosts == ["air"])
            #expect(config.isMuted("air"))
            #expect(!config.isMuted("studio"))
            #expect(!config.isMuted("local"))
            #expect(!config.isMuted("nowhere"))
            let events = [event("local", "a"), event("air", "b"), event("studio", "c")]
            #expect(config.unmuted(events).map(\.ref.host) == ["local", "studio"])
        }
    }

    /// `ccc hosts mute air` then a reload: the mark survives the file, and
    /// unmuting drops the key rather than writing `false` (the file stays
    /// as small as before the feature existed).
    @Test func muteRoundTripsThroughTheFile() throws {
        try withTempConfig(#"{"hosts":[{"name":"air","ssh":"air","claude":"~/.local/bin/claude"}]}"#) { path in
            var config = HostConfig.load(path: path).config
            let set = config.setMuted("air", true)
            #expect(set)
            let unknown = config.setMuted("nowhere", true)
            #expect(!unknown)
            try config.save(path: path)
            let again = HostConfig.load(path: path).config
            #expect(again.mutedHosts == ["air"])
            var back = again
            back.setMuted("air", false)
            try back.save(path: path)
            let text = try String(contentsOfFile: path, encoding: .utf8)
            #expect(!text.contains("mute"))
            #expect(HostConfig.load(path: path).config.mutedHosts.isEmpty)
        }
    }

    /// This Mac can be muted too: `local` is inserted by `load` when the
    /// file forgets it, so the mark has a row to live on and is saved.
    @Test func thisMacIsAHostThatCanBeMuted() throws {
        try withTempConfig(#"{"hosts":[{"name":"air","ssh":"air","claude":"~/.local/bin/claude"}]}"#) { path in
            var config = HostConfig.load(path: path).config
            let set = config.setMuted(Host.localName, true)
            #expect(set)
            try config.save(path: path)
            let again = HostConfig.load(path: path).config
            #expect(again.isMuted(Host.localName))
            #expect(again.unmuted([event("local", "a"), event("air", "b")]).map(\.ref.host) == ["air"])
        }
    }

    /// The detector never consults the mute: a muted host's events are
    /// still detected (the status item counts them, `ccc watch --all`
    /// prints them) and only dropped at the mouth.
    @Test func theDetectorIsUnaffected() {
        var d = TransitionDetector()
        var p = HostPoll(host: "air")
        p.pollCount = 1
        let working = Session(id: "x", cwd: "/x", kind: .background, startedAt: Date(timeIntervalSince1970: 0), state: .working)
        p.rows = [SessionRow(session: working, host: "air", model: nil, attached: false)]
        _ = d.observe(.init(hosts: [p]))
        var blocked = working
        blocked.state = .blocked
        p.rows = [SessionRow(session: blocked, host: "air", model: nil, attached: false)]
        let events = d.observe(.init(hosts: [p]))
        #expect(events.count == 1)
        var config = HostConfig(hosts: [.local, Host(name: "air", ssh: "air", claude: "/c")])
        config.setMuted("air", true)
        #expect(config.unmuted(events).isEmpty)
        #expect(HostConfig(hosts: []).unmuted(events) == events)
    }
}
