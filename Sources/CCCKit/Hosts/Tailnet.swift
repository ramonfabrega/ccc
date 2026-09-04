import Foundation

/// The tailnet, as a list of Macs you might add (queue item 3, the picker).
///
/// `hosts.json` is hand-editable on purpose and one line adds a Mac; this is
/// the other half — the part that saves you looking up an address. It only
/// ever *enumerates*. Deciding whether a machine can actually serve is
/// `ccc hosts add`'s job, which probes over the real ssh for `claude`, `ccc`
/// and `$HOME` and refuses what does not answer (experiment 3).
///
/// **The tailnet cannot tell us who runs an sshd.** Measured 2026-09-04:
/// `tailscale status --json` carries `HostName`, `DNSName`, `OS`, `Online`,
/// `LastSeen`, `Expired` — and no host keys, no "offers SSH", nothing about
/// port 22. A Mac with Remote Login off is indistinguishable here from one
/// with it on. So this list is *candidates*, never *servers*, and the probe
/// stays the gate. Anything else would be a guess wearing a filter's clothes.
///
/// Two things it does know, and both are worth using instead of a heuristic:
/// a node whose key expired says `Expired` (mbp's expired 2025-07-26, so it
/// is dropped for a reason a machine can check rather than for being old),
/// and `LastSeen` dates the offline ones.
public enum Tailnet {
    /// One Mac on the tailnet.
    public struct Peer: Sendable, Equatable, Codable {
        /// The first label of `DNSName` — `studio`, `air`, `mbp`.
        ///
        /// **Not `HostName`**, which is whatever the machine calls itself:
        /// "Ramon's Mac Studio" here, and "localhost" for the iPhone. The
        /// MagicDNS label is the one that is both a legal `Host.name` and a
        /// working ssh destination, which is the whole reason to prefer it.
        public var name: String
        /// The full MagicDNS name, `studio.bengal-barb.ts.net`, trailing dot
        /// removed. **Shown, not used as the ssh destination** — `name` is.
        ///
        /// That is the opposite of what it looks like, and it was measured
        /// 2026-09-04: `ccc hosts add studio --ssh studio.bengal-barb.ts.net`
        /// fails with *Host key verification failed*, because `known_hosts`
        /// and `~/.ssh/config` are keyed on the short label a human types —
        /// the full name is a different host to ssh, with no key on file and
        /// no `User` line. The short label is what v9 slice 1 used, what
        /// resolves through the tailnet's search domain, and what works.
        public var dnsName: String
        /// What the machine calls itself. Shown, never used as an address.
        public var hostName: String
        public var online: Bool
        /// When the coordination server last heard from it, or nil when it
        /// reported the zero date — which in practice means **this Mac**.
        /// An online *peer* still carries a real one (air's is minutes old),
        /// so this is not the inverse of `online`: only `online` says
        /// whether a machine is up. Worth showing on the offline rows and
        /// ignoring on the rest.
        public var lastSeen: Date?
        /// This Mac. Listed rather than hidden: registering yourself is the
        /// loopback hop, which is how the remote path is tested from one
        /// machine (docs/EVIDENCE.md "v9 slice 1 — the hop is real" was
        /// benched studio→studio).
        public var isSelf: Bool

        public init(name: String, dnsName: String, hostName: String,
                    online: Bool, lastSeen: Date? = nil, isSelf: Bool = false) {
            self.name = name
            self.dnsName = dnsName
            self.hostName = hostName
            self.online = online
            self.lastSeen = lastSeen
            self.isSelf = isSelf
        }
    }

    /// `tailscale status --json`, decoded the way the roster is: leniently,
    /// keeping what parses and dropping what does not, because this is
    /// another program's undocumented output and a shape change must not be
    /// a crash (CLAUDE.md's boundary-parsing rule).
    struct Status: Decodable {
        var BackendState: String?
        var Self_: Node?
        var Peer: [String: Node]?

        enum CodingKeys: String, CodingKey {
            case BackendState
            case Self_ = "Self"
            case Peer
        }

        struct Node: Decodable {
            var HostName: String?
            var DNSName: String?
            var OS: String?
            var Online: Bool?
            var LastSeen: String?
            var Expired: Bool?
        }
    }

    /// Macs worth offering, this one included, online first and then by name.
    ///
    /// Dropped: anything not macOS (the iPhone, and two tagged Linux boxes
    /// that cannot run `claude`), anything whose node key has expired, and
    /// anything with no usable MagicDNS label — there would be nothing to
    /// ssh to.
    public static func peers(from json: Data) throws -> [Peer] {
        let status = try JSONDecoder().decode(Status.self, from: json)
        var out: [Peer] = []
        if let node = status.Self_, let peer = peer(from: node, isSelf: true) { out.append(peer) }
        for node in (status.Peer ?? [:]).values.sorted(by: { ($0.DNSName ?? "") < ($1.DNSName ?? "") }) {
            if let peer = peer(from: node, isSelf: false) { out.append(peer) }
        }
        return out.sorted {
            $0.online == $1.online ? $0.name < $1.name : ($0.online && !$1.online)
        }
    }

    private static func peer(from node: Status.Node, isSelf: Bool) -> Peer? {
        guard node.OS == "macOS", node.Expired != true else { return nil }
        let dns = (node.DNSName ?? "").hasSuffix(".")
            ? String((node.DNSName ?? "").dropLast()) : (node.DNSName ?? "")
        guard let label = dns.split(separator: ".").first, !label.isEmpty else { return nil }
        let name = String(label)
        // The label has to survive `ccc attach <host>:<id>` and a hand-edit
        // of hosts.json, so it is held to the same rule a typed name is —
        // `Host.validate`'s name half, which is all of it that applies to a
        // candidate with no claude path yet.
        guard name.contains(":") == false, !name.contains(where: \.isWhitespace) else { return nil }
        return Peer(
            name: name, dnsName: dns, hostName: node.HostName ?? name,
            // Self reports Online true and a zero LastSeen; so does any peer
            // that is up. A zero date is "no answer", not 1 January year 1.
            online: node.Online ?? false, lastSeen: date(node.LastSeen), isSelf: isSelf)
    }

    /// Tailscale's RFC 3339, with the zero value read as nil.
    private static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.hasPrefix("0001-01-01") else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    /// Where the CLI lives. The app bundle's copy is the one a Mac App Store
    /// install has, and `/usr/local/bin` the one the standalone package
    /// writes; neither is on a non-interactive PATH, the same lesson
    /// `Host.claude` learned in experiment 3.
    public static let candidates = [
        "/usr/local/bin/tailscale",
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/opt/homebrew/bin/tailscale",
    ]

    public struct NotInstalled: Error, CustomStringConvertible {
        public var description: String {
            "no tailscale found (looked in \(Tailnet.candidates.joined(separator: ", ")))"
        }
    }

    public struct Unreachable: Error, CustomStringConvertible {
        public var reason: String
        public var description: String { "tailscale did not answer: \(reason)" }
    }

    /// Ask the local tailscale. Never a network call of ours — the daemon
    /// already knows, and this is the same read the `tailscale status`
    /// command a human would type performs.
    public static func scan() throws -> [Peer] {
        guard let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { throw NotInstalled() }

        let process = Process()
        process.executableURL = URL(filePath: binary)
        process.arguments = ["status", "--json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw Unreachable(reason: "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Unreachable(reason: "`tailscale status --json` exited \(process.terminationStatus)")
        }
        return try peers(from: data)
    }
}
