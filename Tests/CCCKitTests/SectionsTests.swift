import Foundation
import Testing

@testable import CCCKit

/// Group and sort (v4 slice 2): one definition behind the View menu and
/// `ccc list --group/--sort`. Pure over a `RosterPoller.State`, so these
/// build one by hand.
@Suite struct SectionsTests {
    private func row(_ id: String, host: String = Host.localName, name: String? = nil, cwd: String = "/Users/x/code/a",
                     state: Session.State? = .done, pid: Int32? = nil, started: TimeInterval, pinned: Bool = false,
                     archived: Bool = false) -> SessionRow {
        SessionRow(session: Session(id: id, cwd: cwd, kind: .background, startedAt: Date(timeIntervalSince1970: started),
                                    state: state, pid: pid, name: name),
                   host: host, model: nil, attached: false, archived: archived, pinned: pinned)
    }

    private func state(_ rows: [SessionRow]) -> RosterPoller.State {
        var byHost: [String: HostPoll] = [:]
        for row in rows { byHost[row.host, default: HostPoll(host: row.host)].rows.append(row) }
        return RosterPoller.State(hosts: byHost.values.sorted { $0.host < $1.host })
    }

    private var sample: RosterPoller.State {
        state([
            row("d1", name: "delta", cwd: "/Users/x/code/a", state: .done, started: 400),
            row("b1", name: "bravo", cwd: "/Users/x/code/b/.claude/worktrees/one", state: .blocked, started: 100),
            row("w1", name: "alpha", cwd: "/Users/x/code/a/.claude/worktrees/two", state: .working, pid: 1, started: 300),
            row("s1", host: "studio", name: "charlie", cwd: "/Users/y/code/c", state: .stopped, started: 200, pinned: true),
            row("z1", name: "zulu", cwd: "/Users/x/code/a", state: .done, started: 500, archived: true),
        ])
    }

    @Test func activityIsTheV0OrderWithPinnedFirst() {
        #expect(sample.rows(sortedBy: .activity).map(\.session.id) == ["s1", "b1", "w1", "z1", "d1"])
    }

    @Test func theOtherSortsKeepPinnedFirstAndBreakTiesNewestFirst() {
        #expect(sample.rows(sortedBy: .name).map(\.session.id) == ["s1", "w1", "b1", "d1", "z1"])
        #expect(sample.rows(sortedBy: .started).map(\.session.id) == ["s1", "z1", "d1", "w1", "b1"])
        #expect(sample.rows(sortedBy: .folder).map(\.session.id) == ["s1", "z1", "d1", "w1", "b1"])
    }

    @Test func noGroupIsOneUntitledSectionWithTheFold() {
        let flat = sample.sections(group: .none, sort: .activity, archived: false)
        #expect(flat.count == 1 && flat[0].title == "")
        #expect(flat[0].rows.map(\.session.id) == ["s1", "b1", "w1", "d1"])
        #expect(sample.sections(group: .none, sort: .activity, archived: true)[0].rows.count == 5)
        #expect(state([]).sections(group: .none, sort: .activity, archived: false).isEmpty)
    }

    @Test func hostSectionsPutLocalFirst() {
        let sections = sample.sections(group: .host, sort: .activity, archived: false)
        #expect(sections.map(\.title) == [Host.localName, "studio"])
        #expect(sections[1].rows.map(\.session.id) == ["s1"])
    }

    /// The harness's worktrees fold into their repo, and the sections
    /// follow the sort: under `activity` the repo with the blocked row
    /// leads even though its only row is the oldest.
    @Test func repoSectionsFoldWorktreesAndFollowTheSort() {
        let sections = sample.sections(group: .repo, sort: .activity, archived: false) { cwd, host in
            host == "studio" ? cwd.replacingOccurrences(of: "/Users/y", with: "~") : cwd.replacingOccurrences(of: "/Users/x", with: "~")
        }
        #expect(sections.map(\.title) == ["~/code/c", "~/code/b", "~/code/a"])
        #expect(sections[2].rows.map(\.session.id) == ["w1", "d1"])
    }

    @Test func stateSectionsAreFixedInOrderAndArchivedIsItsOwn() {
        let hidden = sample.sections(group: .state, sort: .activity, archived: false)
        #expect(hidden.map(\.title) == ["waiting", "working", "finished"])
        let shown = sample.sections(group: .state, sort: .activity, archived: true)
        #expect(shown.map(\.title) == ["waiting", "working", "finished", "archived"])
        #expect(shown[3].rows.map(\.session.id) == ["z1"])
        // Pinned but stopped is still "finished": the sections are by state, the pin orders within.
        #expect(shown[2].rows.map(\.session.id) == ["s1", "d1"])
        // A blocked row is never hidden, so an archived blocked row sits with the waiting.
        let blockedArchived = state([row("q", state: .blocked, started: 1, archived: true)])
        #expect(blockedArchived.sections(group: .state, sort: .activity, archived: false).map(\.title) == ["waiting"])
    }

    @Test func repoPathReadsTheHarnessConvention() {
        #expect(RepoPath.root(of: "/x/ccc/.claude/worktrees/v2") == "/x/ccc")
        #expect(RepoPath.root(of: "/x/ccc/.claude/worktrees/v2/Sources") == "/x/ccc")
        #expect(RepoPath.root(of: "/x/ccc") == "/x/ccc")
        #expect(RepoPath.worktree(of: "/x/ccc/.claude/worktrees/v2/Sources") == "v2")
        #expect(RepoPath.worktree(of: "/x/ccc") == nil)
    }

    @Test func theRawValuesAreTheFlagWords() {
        #expect(RosterSort(rawValue: "folder") == .folder)
        #expect(RosterGroup(rawValue: "repo") == .repo)
        #expect(RosterGroup.allCases.map(\.rawValue) == ["none", "host", "repo", "state"])
    }
}
