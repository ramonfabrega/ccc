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

    private enum CodingKeys: String, CodingKey {
        case id, cwd, kind, startedAt, state, status, pid, waitingFor, sessionId, name, extra
    }

    /// The Codable face is the wire between two builds of ccc — what
    /// `ccc list --json` writes and the far side's poller reads — and it
    /// is lenient the way `RosterDecoder` is for the harness's shape. A
    /// word this build does not know (`state`, `status`, `kind` from a
    /// newer ccc that learned a new value first) is parked in `extra`
    /// under its key and the row stands; a missing `extra` is none. Only
    /// `id`, `cwd` and `startedAt` are required, and losing them loses
    /// the one row, never the array (`LenientElement`). Until 2026-09-04
    /// this was the synthesised decoder, and one new enum value on the
    /// far side threw the whole remote roster away.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        cwd = try c.decode(String.self, forKey: .cwd)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        var extra = try c.decodeIfPresent([String: JSONValue].self, forKey: .extra) ?? [:]
        func word<E: RawRepresentable>(_ key: CodingKeys, _: E.Type) throws -> E? where E.RawValue == String {
            guard let raw = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
            if let parsed = E(rawValue: raw) { return parsed }
            extra[key.stringValue] = .string(raw)
            return nil
        }
        kind = try word(.kind, Kind.self) ?? .background
        state = try word(.state, State.self)
        status = try word(.status, Status.self)
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
        waitingFor = try c.decodeIfPresent(String.self, forKey: .waitingFor)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        self.extra = extra
    }
}

/// One element of a JSON array that must not take the array down with it.
/// Decoding `[LenientElement<Row>]` never throws for a bad element: the
/// element carries `nil` and the reason instead, and the caller turns
/// that into one banner line. This is the "never an empty list" rule
/// (CLAUDE.md) applied to the wire between two builds of ccc.
public struct LenientElement<Value: Decodable>: Decodable {
    public let value: Value?
    public let error: String?

    public init(from decoder: Decoder) {
        do {
            value = try Value(from: decoder)
            error = nil
        } catch {
            value = nil
            self.error = Self.describe(error)
        }
    }

    /// A `DecodingError` said in one line with its path — `session.state:
    /// Cannot initialize State from invalid String value "parked"` —
    /// where `localizedDescription` says only "The data couldn't be
    /// read because it isn't in the correct format."
    public static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return "\(error)" }
        let context: DecodingError.Context
        switch decoding {
        case .dataCorrupted(let c), .keyNotFound(_, let c), .typeMismatch(_, let c), .valueNotFound(_, let c):
            context = c
        @unknown default:
            return "\(error)"
        }
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
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
