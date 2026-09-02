import Foundation

/// Where a session is: the host it runs on plus the harness's short id.
///
/// v0 and v1 addressed a session by its short id alone, which only holds
/// while one daemon is in view. Two Macs each run their own daemon and each
/// mints its own ids, so `a1b2` stops being an address the moment a second
/// host appears — nothing prevents both from having one. This is the address
/// from here on: `studio:a1b2` written out, `a1b2` when it is local.
///
/// The local form is deliberately bare, so everything a v1 hand or script
/// already types (`ccc attach a1b2`) keeps meaning what it meant, and a
/// one-Mac roster reads exactly as it did.
public struct SessionRef: Sendable, Equatable, Hashable, CustomStringConvertible {
    public var host: String
    public var id: String

    public init(host: String = Host.localName, id: String) {
        self.host = host
        self.id = id
    }

    public var isLocal: Bool { host == Host.localName }

    public var description: String { isLocal ? id : "\(host):\(id)" }

    /// Parses `id` or `host:id`. Returns nil for anything that is not an
    /// address — an empty half, or more than one `:` (which is why a host
    /// name may not contain one, see `Host.validate`).
    public static func parse(_ text: String) -> SessionRef? {
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            return SessionRef(id: String(parts[0]))
        case 2:
            let host = String(parts[0]), id = String(parts[1])
            guard !host.isEmpty, !id.isEmpty else { return nil }
            return SessionRef(host: host, id: id)
        default:
            return nil
        }
    }
}

/// One string on the wire and in every `--json` payload (`"studio:a1b2"`),
/// not a nested object: an address a human reads is an address an agent can
/// paste straight back into `ccc attach`.
extension SessionRef: Codable {
    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let ref = SessionRef.parse(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "'\(text)' is not a session ref (id or host:id)"))
        }
        self = ref
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
