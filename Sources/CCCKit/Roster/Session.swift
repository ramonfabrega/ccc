import Foundation

/// One element of `claude agents --json --all`, decoded leniently
/// (docs/HARNESS.md). Known fields are typed; everything else survives in
/// `extra` so nothing the daemon adds is lost, and a field that goes missing
/// or changes type is a `RosterShapeIssue`, never a crash.
///
/// Always present per the harness docs: `cwd`, `kind`, `startedAt`.
/// Background sessions add `id`, `state`. Live processes add `pid`, `status`.
public struct Session: Codable, Sendable, Equatable, Identifiable {
    public var id: String            // short id (background); falls back to sessionId, then cwd+startedAt
    public var cwd: String
    public var kind: Kind
    public var startedAt: Date
    public var state: State?
    public var status: Status?
    public var pid: Int32?
    public var waitingFor: String?
    public var sessionId: String?
    public var name: String?
    /// Unknown fields, preserved verbatim.
    public var extra: [String: JSONValue]

    public enum Kind: String, Codable, Sendable { case interactive, background }
    public enum State: String, Codable, Sendable { case working, blocked, done, failed, stopped }
    /// `waiting` was found by the banner, not by reading docs: on
    /// 2026-09-02 a `blocked` row with `waitingFor: "input needed"` came
    /// back as `status: "waiting"`, which the decoder flagged as an unknown
    /// value. It is a known one now (docs/HARNESS.md).
    public enum Status: String, Codable, Sendable { case busy, idle, waiting }

    public init(id: String, cwd: String, kind: Kind, startedAt: Date, state: State? = nil,
                status: Status? = nil, pid: Int32? = nil, waitingFor: String? = nil,
                sessionId: String? = nil, name: String? = nil, extra: [String: JSONValue] = [:]) {
        self.id = id
        self.cwd = cwd
        self.kind = kind
        self.startedAt = startedAt
        self.state = state
        self.status = status
        self.pid = pid
        self.waitingFor = waitingFor
        self.sessionId = sessionId
        self.name = name
        self.extra = extra
    }
}

/// Untyped JSON, for the fields we do not know about.
public indirect enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])
}

/// Why the roster did not decode as expected. Rendered as the "roster shape
/// changed" banner; the rows that did decode are still shown.
public struct RosterShapeIssue: Sendable, Equatable, Codable, CustomStringConvertible {
    public var index: Int?          // element index, nil for top-level
    public var field: String?
    public var message: String
    public init(index: Int? = nil, field: String? = nil, message: String) {
        self.index = index
        self.field = field
        self.message = message
    }
    public var description: String {
        var s = message
        if let field { s = "\(field): \(s)" }
        if let index { s = "[\(index)] \(s)" }
        return s
    }
}

public struct RosterDecodeResult: Sendable, Equatable {
    public var sessions: [Session]
    public var issues: [RosterShapeIssue]
    public init(sessions: [Session], issues: [RosterShapeIssue]) {
        self.sessions = sessions
        self.issues = issues
    }
}
