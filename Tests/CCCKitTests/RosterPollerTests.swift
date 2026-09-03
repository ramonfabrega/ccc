import Foundation
import Testing

@testable import CCCKit

/// The fan-out (docs/DESIGN.md §4b): one slot per host, merged when read,
/// so a host that is asleep or broken can only ever affect itself. These
/// drive real `HostPoller`s against a fake `claude` — a shell script that
/// prints a roster — because the merge rules are only worth pinning
/// against the code path the app runs.
@Suite struct RosterPollerTests {
    private static let roster = """
    [{"id":"a1b2","cwd":"/Users/x/code","kind":"background","startedAt":"2026-09-02T07:20:04.000Z",
      "state":"working","status":"busy","sessionId":"aaaaaaaa-0000-0000-0000-000000000000"},
     {"id":"c3d4","cwd":"/Users/x/other","kind":"background","startedAt":"2026-09-02T06:20:04.000Z",
      "state":"done"}]
    """

    /// A `claude` that answers `agents --json --all` with a fixed roster.
    private func fakeClaude(in dir: URL, printing json: String = roster) throws -> String {
        let path = dir.appending(path: "claude").path
        let script = "#!/bin/sh\ncat <<'EOF'\n\(json)\nEOF\n"
        try Data(script.utf8).write(to: URL(filePath: path))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    @MainActor private func withTempDir(_ body: @MainActor (URL) async throws -> Void) async throws {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-poll-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir)
    }

    @Test @MainActor func oneBrokenHostNeverBlanksTheOthers() async throws {
        try await withTempDir { dir in
            let good = HostPoller(cli: ClaudeCLI(executable: try fakeClaude(in: dir), host: .local))
            // No such binary: the poll fails before it starts.
            let bad = HostPoller(cli: ClaudeCLI(executable: dir.appending(path: "missing").path,
                                                host: Host(name: "ghost")), hostName: "ghost")
            let fleet = RosterPoller(pollers: [good, bad])
            await fleet.tick()
            let state = fleet.state
            #expect(state.rows.count == 2)
            #expect(state.rows.allSatisfy { $0.host == Host.localName })
            #expect(state.failures.map(\.host) == ["ghost"])
            #expect(state.host("ghost")?.error != nil)
            #expect(state.host("ghost")?.failures == 1)
            // Not a roster-wide error: one host answered.
            #expect(state.error == nil)
            #expect(state.anyHostAnswered)
            // The footer's number is the answering host's, not the failure's.
            #expect(state.lastPollMs == state.host(Host.localName)?.lastPollMs)
        }
    }

    @Test @MainActor func everyHostFailingIsTheOnlyRosterWideError() async throws {
        try await withTempDir { dir in
            let missing = dir.appending(path: "missing").path
            let fleet = RosterPoller(pollers: [
                HostPoller(cli: ClaudeCLI(executable: missing, host: .local)),
                HostPoller(cli: ClaudeCLI(executable: missing, host: Host(name: "ghost")), hostName: "ghost"),
            ])
            await fleet.tick()
            #expect(fleet.state.error?.contains("ghost:") == true)
            #expect(!fleet.state.anyHostAnswered)
            #expect(fleet.state.rows.isEmpty)
        }
    }

    /// A host that answered and then stopped keeps its last rows, marked
    /// stale — a sleeping Mac still has its sessions, and a minute-old row
    /// beats an empty list.
    @Test @MainActor func rowsSurviveAFailedPollAsStale() async throws {
        try await withTempDir { dir in
            let path = try fakeClaude(in: dir)
            let poller = HostPoller(cli: ClaudeCLI(executable: path, host: Host(name: "studio")), hostName: "studio")
            await poller.tick()
            #expect(poller.state.rows.count == 2)
            #expect(poller.state.rows.allSatisfy { $0.host == "studio" })
            #expect(!poller.state.isStale)
            let firstSuccess = poller.state.lastSuccessAt

            try FileManager.default.removeItem(atPath: path)
            await poller.tick()
            #expect(poller.state.error != nil)
            #expect(poller.state.rows.count == 2)
            #expect(poller.state.isStale)
            #expect(poller.state.lastSuccessAt == firstSuccess)
            #expect(poller.state.pollCount == 2)

            // And it comes back clean.
            _ = try fakeClaude(in: dir)
            await poller.tick()
            #expect(poller.state.error == nil)
            #expect(!poller.state.isStale)
            #expect(poller.state.failures == 0)
        }
    }

    /// Two ticks asked for at once on one host run one poll, not two: the
    /// second caller waits for the first. A 5 s timeout on a sleeping Mac
    /// must never stack ssh processes behind a 2 s interval.
    @Test @MainActor func concurrentTicksOnOneHostShareOnePoll() async throws {
        try await withTempDir { dir in
            let path = try fakeClaude(in: dir)
            // Slow enough that the second tick certainly overlaps.
            let script = "#!/bin/sh\nsleep 0.3\ncat <<'EOF'\n\(Self.roster)\nEOF\n"
            try Data(script.utf8).write(to: URL(filePath: path))
            let poller = HostPoller(cli: ClaudeCLI(executable: path, host: .local))
            async let first: Void = poller.tick()
            async let second: Void = poller.tick()
            _ = await (first, second)
            #expect(poller.state.pollCount == 1)
            #expect(poller.state.rows.count == 2)
        }
    }

    @Test @MainActor func theMergedViewSortsAcrossHosts() async throws {
        try await withTempDir { dir in
            let local = HostPoller(cli: ClaudeCLI(executable: try fakeClaude(in: dir), host: .local))
            let remoteDir = dir.appending(path: "remote")
            try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
            let blocked = """
            [{"id":"e5f6","cwd":"/Users/y","kind":"background","startedAt":"2026-09-01T07:20:04.000Z",
              "state":"blocked","waitingFor":"input needed"}]
            """
            let remote = HostPoller(cli: ClaudeCLI(executable: try fakeClaude(in: remoteDir, printing: blocked),
                                                   host: Host(name: "studio")), hostName: "studio")
            let fleet = RosterPoller(pollers: [local, remote])
            await fleet.tick()
            let sorted = fleet.state.sorted
            #expect(sorted.count == 3)
            // Blocked outranks working regardless of host or age.
            #expect(sorted.first?.ref == SessionRef(host: "studio", id: "e5f6"))
            #expect(sorted.last?.session.id == "c3d4")
        }
    }

    @Test @MainActor func attachedRefReachesEveryHost() async throws {
        try await withTempDir { dir in
            let fleet = RosterPoller(pollers: [
                HostPoller(cli: ClaudeCLI(executable: try fakeClaude(in: dir), host: .local)),
                HostPoller(cli: ClaudeCLI(executable: try fakeClaude(in: dir), host: Host(name: "studio")), hostName: "studio"),
            ])
            fleet.attachedRef = SessionRef(host: "studio", id: "a1b2")
            await fleet.tick()
            let attached = fleet.state.rows.filter(\.attached).map(\.ref)
            #expect(attached == [SessionRef(host: "studio", id: "a1b2")])
        }
    }

    // MARK: the overlay (v4)

    /// The local host joins our marks from the overlay file, re-reading it
    /// when it changes — `ccc archive` from a shell shows in the window a
    /// tick later. A pinned row sorts first; an archived one leaves
    /// `visible` but never `sorted` (which is what crosses the hop).
    @Test @MainActor func localRowsCarryTheOverlaysMarks() async throws {
        try await withTempDir { dir in
            let overlayPath = dir.appending(path: "roster.json").path
            let poller = HostPoller(cli: ClaudeCLI(executable: try fakeClaude(in: dir), host: .local), overlayPath: overlayPath)
            let fleet = RosterPoller(pollers: [poller])
            await fleet.tick()
            #expect(fleet.state.sorted.map(\.session.id) == ["a1b2", "c3d4"])
            #expect(fleet.state.hiddenCount == 0)

            var overlay = RosterOverlay()
            overlay.set(.pin, id: "c3d4", sessionId: nil)
            overlay.set(.archive, id: "a1b2", sessionId: "aaaaaaaa-0000-0000-0000-000000000000")
            try overlay.save(path: overlayPath)
            await fleet.tick()
            // Pinned first, ahead of the working row.
            #expect(fleet.state.sorted.map(\.session.id) == ["c3d4", "a1b2"])
            #expect(fleet.state.sorted.map(\.pinned) == [true, false])
            #expect(fleet.state.sorted.map(\.archived) == [false, true])
            #expect(fleet.state.visible.map(\.session.id) == ["c3d4"])
            #expect(fleet.state.hiddenCount == 1)

            // A mark made against another uuid is not this session's.
            overlay.marks["a1b2"]?.sessionId = "some-earlier-session"
            try overlay.save(path: overlayPath)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: overlayPath)
            await fleet.tick()
            #expect(fleet.state.visible.count == 2)
        }
    }

    /// The file is ours to break by hand; the rows are the harness's and
    /// stay. One note, no error, no exit status.
    @Test @MainActor func aBrokenOverlayIsANoteNotAFailure() async throws {
        try await withTempDir { dir in
            let overlayPath = dir.appending(path: "roster.json").path
            try Data("nope".utf8).write(to: URL(filePath: overlayPath))
            let poller = HostPoller(cli: ClaudeCLI(executable: try fakeClaude(in: dir), host: .local), overlayPath: overlayPath)
            await poller.tick()
            #expect(poller.state.rows.count == 2)
            #expect(poller.state.error == nil)
            #expect(poller.state.notes.count == 1)
            #expect(poller.state.notes.first?.contains("ignoring the overlay") == true)
        }
    }

    // MARK: hosts.json under a running fleet (item 3)

    /// `ccc hosts add studio` from a shell has to reach a running app.
    /// Measured 2026-09-03, the first day a real remote host existed: the
    /// CLI answered `ccc hosts check studio` while the app said "unknown
    /// host 'studio'", because the host list was read once at launch.
    @Test @MainActor func aHostAddedOnDiskJoinsARunningFleet() async throws {
        try await withTempDir { dir in
            let claude = try fakeClaude(in: dir)
            let fleet = RosterPoller(pollers: [HostPoller(cli: ClaudeCLI(executable: claude, host: .local))],
                                     built: [Host.localName: .local])
            fleet.start()
            defer { fleet.stop() }

            let studio = Host(name: "studio", ssh: "studio", claude: claude)
            let changes = fleet.sync(to: HostConfig(hosts: [.local, studio])) { host in
                HostPoller(cli: ClaudeCLI(executable: claude, host: host), hostName: host.name)
            }
            #expect(changes.added == ["studio"])
            #expect(changes.removed.isEmpty)
            #expect(changes.said == "hosts: added studio")
            #expect(fleet.pollers.map(\.hostName) == [Host.localName, "studio"])
            // The new slot is polling, not waiting for the next launch.
            await fleet.tick()
            #expect(fleet.state.host("studio")?.rows.count == 2)
        }
    }

    /// A removed host stops being polled and its rows leave. What it must
    /// *not* do is take a live attach with it — the pane owns its own argv,
    /// which is the whole reason reloading is safe.
    @Test @MainActor func aHostRemovedOnDiskStopsBeingPolled() async throws {
        try await withTempDir { dir in
            let claude = try fakeClaude(in: dir)
            let studio = Host(name: "studio", ssh: "studio", claude: claude)
            let make: (CCCKit.Host) -> HostPoller = { host in
                HostPoller(cli: ClaudeCLI(executable: claude, host: host), hostName: host.name)
            }
            let config = HostConfig(hosts: [.local, studio])
            let fleet = RosterPoller(pollers: config.hosts.map(make),
                                     built: Dictionary(uniqueKeysWithValues: config.hosts.map { ($0.name, $0) }))
            await fleet.tick()
            #expect(fleet.state.rows.count == 4)

            let changes = fleet.sync(to: HostConfig(hosts: [.local]), make: make)
            #expect(changes.removed == ["studio"])
            #expect(changes.said == "hosts: dropped studio")
            #expect(fleet.pollers.map(\.hostName) == [Host.localName])
            #expect(fleet.state.rows.count == 2)
        }
    }

    /// Editing a host's ssh destination or claude path has to replace its
    /// poller: keeping the old one would leave the roster reading the
    /// command the user just changed. A host that only moved in the file
    /// keeps its slot, and with it its counters.
    @Test @MainActor func anEditedHostIsRebuiltAndAMovedOneIsNot() async throws {
        try await withTempDir { dir in
            let claude = try fakeClaude(in: dir)
            let studio = Host(name: "studio", ssh: "studio", claude: claude)
            let make: (CCCKit.Host) -> HostPoller = { host in
                HostPoller(cli: ClaudeCLI(executable: claude, host: host), hostName: host.name)
            }
            let config = HostConfig(hosts: [.local, studio])
            let fleet = RosterPoller(pollers: config.hosts.map(make),
                                     built: Dictionary(uniqueKeysWithValues: config.hosts.map { ($0.name, $0) }))
            await fleet.tick()
            #expect(fleet.state.host("studio")?.pollCount == 1)

            // Reordered only: same hosts, same slots, counters intact.
            let reordered = fleet.sync(to: HostConfig(hosts: [studio, .local]), make: make)
            #expect(reordered.isEmpty)
            #expect(reordered.said == nil)
            #expect(fleet.pollers.map(\.hostName) == ["studio", Host.localName])
            #expect(fleet.state.host("studio")?.pollCount == 1)

            // The ssh destination moved: a fresh slot, so a fresh count.
            var moved = studio
            moved.ssh = "studio.tail-scale.ts.net"
            let changes = fleet.sync(to: HostConfig(hosts: [.local, moved]), make: make)
            #expect(changes.replaced == ["studio"])
            #expect(changes.said == "hosts: reloaded studio")
            #expect(fleet.state.host("studio")?.pollCount == 0)
        }
    }

    /// A fleet that was never started does not start pollers behind the
    /// user's back: `ccc list` syncs and ticks once, and must not leave a
    /// 2 s loop running in a process that is about to print and exit.
    @Test @MainActor func aStoppedFleetAddsAStoppedPoller() async throws {
        try await withTempDir { dir in
            let claude = try fakeClaude(in: dir)
            let fleet = RosterPoller(pollers: [HostPoller(cli: ClaudeCLI(executable: claude, host: .local))],
                                     built: [Host.localName: .local])
            let studio = Host(name: "studio", ssh: "studio", claude: claude)
            fleet.sync(to: HostConfig(hosts: [.local, studio])) { host in
                HostPoller(cli: ClaudeCLI(executable: claude, host: host), hostName: host.name)
            }
            #expect(fleet.pollers.count == 2)
            // Nothing has polled: no loop was started for the new slot.
            try await Task.sleep(for: .milliseconds(300))
            #expect(fleet.state.host("studio")?.pollCount == 0)
        }
    }
}
