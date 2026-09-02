import Foundation

/// How the roster is ordered (v4 slice 2). One definition for both faces:
/// the window's View menu and `ccc list --sort`. Pinned rows come first
/// under every order — the pin is "keep this at the top", whatever the
/// rest is sorted by.
public enum RosterSort: String, Codable, Sendable, CaseIterable {
    /// Blocked, then working, then failed, then done/stopped; newest
    /// first within a rank. The v0 order, and still the default.
    case activity
    /// By the session's name (its id when unnamed), case-insensitive.
    case name
    /// Newest start first, whatever its state.
    case started
    /// By working directory, newest first within one.
    case folder

    public var label: String {
        switch self {
        case .activity: return "Activity"
        case .name: return "Name"
        case .started: return "Started"
        case .folder: return "Folder"
        }
    }
}

/// How the roster is sectioned. `none` is the flat list every version so
/// far has shown. Grouping is presentation: `--json` stays a flat list in
/// the requested sort, and a machine groups for itself.
public enum RosterGroup: String, Codable, Sendable, CaseIterable {
    case none
    /// One section per host, `local` first.
    case host
    /// One section per repository: a worktree under `.claude/worktrees/`
    /// folds into the repo it belongs to (`RepoPath.root`), so the eight
    /// sessions on one project's worktrees sit under one heading.
    case repo
    /// Waiting / working / finished / archived.
    case state

    public var label: String {
        switch self {
        case .none: return "None"
        case .host: return "Host"
        case .repo: return "Repository"
        case .state: return "State"
        }
    }
}

public struct RosterSection: Sendable, Equatable, Identifiable {
    public var title: String
    public var rows: [SessionRow]
    public var id: String { title }
    public init(title: String, rows: [SessionRow]) {
        self.title = title
        self.rows = rows
    }
}

/// The harness's worktree convention (`<repo>/.claude/worktrees/<name>`),
/// read off a cwd. That is the only convention ccc knows: a session in a
/// worktree made by hand elsewhere is its own "repo", which is honest.
public enum RepoPath {
    static let marker = "/.claude/worktrees/"

    /// `/x/ccc/.claude/worktrees/v2/Sources` → `/x/ccc`; anything else as is.
    public static func root(of cwd: String) -> String {
        guard let range = cwd.range(of: marker) else { return cwd }
        return String(cwd[..<range.lowerBound])
    }

    /// The worktree's name when the cwd is in one (`v2` above), else nil.
    public static func worktree(of cwd: String) -> String? {
        guard let range = cwd.range(of: marker) else { return nil }
        let rest = cwd[range.upperBound...]
        let name = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first
        return name.map(String.init)
    }
}

extension RosterPoller.State {
    /// Every row in one order. Pinned first; then the sort's key; then
    /// newest first as the tie-break every sort shares.
    public func rows(sortedBy sort: RosterSort) -> [SessionRow] {
        rows.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            switch sort {
            case .activity:
                let ra = a.session.rank, rb = b.session.rank
                if ra != rb { return ra < rb }
            case .name:
                let na = (a.session.name ?? a.session.id).lowercased(), nb = (b.session.name ?? b.session.id).lowercased()
                if na != nb { return na < nb }
            case .started:
                break
            case .folder:
                if a.session.cwd != b.session.cwd { return a.session.cwd < b.session.cwd }
            }
            return a.session.startedAt > b.session.startedAt
        }
    }

    /// The roster as the window shows it and `ccc list` prints it:
    /// sectioned by `group`, ordered by `sort` within each section, the
    /// sections themselves in the order of their first row (so under
    /// `activity` the repo with a blocked session leads) — except `host`,
    /// which keeps `local` first, and `state`, whose order is fixed.
    /// `archived` false folds the hidden rows away (`SessionRow.isHidden`).
    /// `title` names a group's row: given the cwd shortener of the host
    /// that answered it, since `~` differs per Mac.
    public func sections(group: RosterGroup, sort: RosterSort, archived: Bool,
                         shortCwd: (String, String) -> String = { cwd, _ in cwd }) -> [RosterSection] {
        let ordered = rows(sortedBy: sort).filter { archived || !$0.isHidden }
        switch group {
        case .none:
            return ordered.isEmpty ? [] : [RosterSection(title: "", rows: ordered)]
        case .host:
            var sections = bucket(ordered) { $0.host }
            if let i = sections.firstIndex(where: { $0.title == Host.localName }), i != 0 {
                sections.insert(sections.remove(at: i), at: 0)
            }
            return sections
        case .repo:
            return bucket(ordered) { shortCwd(RepoPath.root(of: $0.session.cwd), $0.host) }
        case .state:
            let order = ["waiting", "working", "finished", "archived"]
            let sections = bucket(ordered) { row in
                if row.isHidden { return "archived" }
                switch row.session.state {
                case .blocked: return "waiting"
                case .working: return "working"
                case nil: return row.session.pid != nil ? "working" : "finished"
                case .done, .failed, .stopped: return "finished"
                }
            }
            return sections.sorted { (order.firstIndex(of: $0.title) ?? 9) < (order.firstIndex(of: $1.title) ?? 9) }
        }
    }

    /// Sections in order of first appearance, rows in the order given.
    private func bucket(_ rows: [SessionRow], by key: (SessionRow) -> String) -> [RosterSection] {
        var order: [String] = []
        var buckets: [String: [SessionRow]] = [:]
        for row in rows {
            let k = key(row)
            if buckets[k] == nil { order.append(k) }
            buckets[k, default: []].append(row)
        }
        return order.map { RosterSection(title: $0, rows: buckets[$0]!) }
    }
}
