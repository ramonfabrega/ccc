import Foundation

/// Lenient decoder for `claude agents --json --all` output.
///
/// Contract (docs/HARNESS.md, CLAUDE.md "Boundary parsing, lenient"):
/// - Top level must be a JSON array. Anything else → one top-level issue,
///   zero sessions.
/// - Each element is decoded as a `JSONValue` object first; known fields are
///   pulled out by name and type-checked; every remaining key lands in
///   `extra` untouched.
/// - `cwd` (string), `kind` (string), `startedAt` (number, epoch ms) are
///   required. A missing or mistyped one is an issue for that element; the
///   element is still emitted when `cwd` is present (with `kind`
///   defaulting to `.background` and `startedAt` to distantPast) so the
///   roster never goes empty because one row changed shape.
/// - Unknown enum strings (`kind`, `state`, `status`) are an issue and
///   decode as nil (or `.background` for kind), with the raw string kept in
///   `extra["<field>"]`.
/// - `id` falls back to `sessionId`, then to `cwd@startedAt`.
/// - Element order is preserved. No sorting here; presentation sorts.
///
/// Refinement of "still emitted when `cwd` is present": a `cwd` that is
/// present but not a string cannot address a session, so it is treated as
/// missing — the issue is recorded, the raw value is preserved in `extra`,
/// and the element is dropped. Every other mistyped field keeps its raw
/// value in `extra` and the row survives.
public enum RosterDecoder {
    public static func decode(_ data: Data) -> RosterDecodeResult {
        guard !data.isEmpty else {
            return RosterDecodeResult(sessions: [], issues: [
                RosterShapeIssue(message: "roster payload was empty")
            ])
        }
        let root: JSONValue
        do {
            root = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            return RosterDecodeResult(sessions: [], issues: [
                RosterShapeIssue(message: "roster payload is not JSON")
            ])
        }
        guard case .array(let elements) = root else {
            return RosterDecodeResult(sessions: [], issues: [
                RosterShapeIssue(message: "top level is \(root.typeName), expected an array")
            ])
        }

        var sessions: [Session] = []
        var issues: [RosterShapeIssue] = []
        for (index, element) in elements.enumerated() {
            var elementIssues: [RosterShapeIssue] = []
            let session = decodeElement(element, at: index, issues: &elementIssues)
            issues.append(contentsOf: elementIssues)
            if let session { sessions.append(session) }
        }
        return RosterDecodeResult(sessions: sessions, issues: issues)
    }

    // MARK: - Element

    private static func decodeElement(
        _ element: JSONValue, at index: Int, issues: inout [RosterShapeIssue]
    ) -> Session? {
        guard case .object(let object) = element else {
            issues.append(RosterShapeIssue(
                index: index, message: "element is \(element.typeName), expected an object"))
            return nil
        }
        var extra = object
        func take(_ key: String) -> JSONValue? { extra.removeValue(forKey: key) }
        /// A known key whose value had the wrong shape stays in `extra` verbatim.
        func keepRaw(_ key: String, _ value: JSONValue) { extra[key] = value }

        // cwd — required, string.
        guard let cwdValue = take("cwd") else {
            issues.append(RosterShapeIssue(index: index, field: "cwd", message: "missing"))
            return nil
        }
        guard case .string(let cwd) = cwdValue else {
            issues.append(RosterShapeIssue(
                index: index, field: "cwd",
                message: "expected a string, got \(cwdValue.typeName)"))
            keepRaw("cwd", cwdValue)
            return nil
        }

        // kind — required, string enum; defaults to .background.
        var kind = Session.Kind.background
        if let kindValue = take("kind") {
            if case .string(let raw) = kindValue {
                if let parsed = Session.Kind(rawValue: raw) {
                    kind = parsed
                } else {
                    issues.append(RosterShapeIssue(
                        index: index, field: "kind", message: "unknown value \"\(raw)\""))
                    keepRaw("kind", kindValue)
                }
            } else {
                issues.append(RosterShapeIssue(
                    index: index, field: "kind",
                    message: "expected a string, got \(kindValue.typeName)"))
                keepRaw("kind", kindValue)
            }
        } else {
            issues.append(RosterShapeIssue(index: index, field: "kind", message: "missing"))
        }

        // startedAt — required, number of epoch milliseconds.
        var startedAt = Date.distantPast
        if let startedValue = take("startedAt") {
            if case .number(let ms) = startedValue {
                startedAt = Date(timeIntervalSince1970: ms / 1000)
            } else {
                issues.append(RosterShapeIssue(
                    index: index, field: "startedAt",
                    message: "expected a number of epoch milliseconds, got \(startedValue.typeName)"))
                keepRaw("startedAt", startedValue)
            }
        } else {
            issues.append(RosterShapeIssue(index: index, field: "startedAt", message: "missing"))
        }

        // Optional strings.
        func optionalString(_ key: String) -> String? {
            guard let value = take(key) else { return nil }
            guard case .string(let s) = value else {
                issues.append(RosterShapeIssue(
                    index: index, field: key,
                    message: "expected a string, got \(value.typeName)"))
                keepRaw(key, value)
                return nil
            }
            return s
        }

        // Optional string enums.
        func optionalEnum<T: RawRepresentable>(_ key: String, _ type: T.Type) -> T?
        where T.RawValue == String {
            guard let value = take(key) else { return nil }
            guard case .string(let raw) = value else {
                issues.append(RosterShapeIssue(
                    index: index, field: key,
                    message: "expected a string, got \(value.typeName)"))
                keepRaw(key, value)
                return nil
            }
            guard let parsed = T(rawValue: raw) else {
                issues.append(RosterShapeIssue(
                    index: index, field: key, message: "unknown value \"\(raw)\""))
                keepRaw(key, value)
                return nil
            }
            return parsed
        }

        let state = optionalEnum("state", Session.State.self)
        let status = optionalEnum("status", Session.Status.self)

        var pid: Int32?
        if let pidValue = take("pid") {
            if case .number(let n) = pidValue, let narrowed = Int32(exactly: n.rounded()) {
                pid = narrowed
            } else {
                issues.append(RosterShapeIssue(
                    index: index, field: "pid",
                    message: "expected a process id, got \(pidValue.typeName)"))
                keepRaw("pid", pidValue)
            }
        }

        let waitingFor = optionalString("waitingFor")
        let sessionId = optionalString("sessionId")
        let name = optionalString("name")
        let explicitID = optionalString("id")

        let id: String
        if let explicitID, !explicitID.isEmpty {
            id = explicitID
        } else if let sessionId, !sessionId.isEmpty {
            id = sessionId
        } else {
            let ms = Int((startedAt.timeIntervalSince1970 * 1000).rounded())
            id = "\(cwd)@\(ms)"
        }

        return Session(
            id: id, cwd: cwd, kind: kind, startedAt: startedAt, state: state, status: status,
            pid: pid, waitingFor: waitingFor, sessionId: sessionId, name: name, extra: extra)
    }
}

// MARK: - JSONValue

extension JSONValue {
    /// The JSON type name, for issue messages.
    var typeName: String {
        switch self {
        case .string: "a string"
        case .number: "a number"
        case .bool: "a boolean"
        case .null: "null"
        case .array: "an array"
        case .object: "an object"
        }
    }
}

/// Hand-written `Codable` so `JSONValue` is *plain* JSON on the wire.
/// The compiler's synthesis for an enum with associated values would emit a
/// tagged form (`{"string":{"_0":"x"}}`); a same-module implementation wins
/// over synthesis, so `{"a":1}` round-trips as an object.
extension JSONValue {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "value is not JSON")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .number(let n): try container.encode(n)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}
