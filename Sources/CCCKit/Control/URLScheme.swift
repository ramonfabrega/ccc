import Foundation

/// `ccc://` — what another app (lore's pages, first) links to. The grammar
/// is one line, so the sites that emit it can copy it rather than read
/// this file:
///
///     ccc://attach/<ref>
///
/// `<ref>` is what `ccc attach` takes — a daemon id or a session name,
/// optionally `<host>:` in front — percent-encoded. It resolves the way
/// the CLI's attach does (`RosterPoller.State.resolve`): local first,
/// then every host, so a bare daemon id from studio's lore attaches from
/// air too. The scheme is registered in the bundle's Info.plist by
/// `scripts/url-scheme`, which `scripts/install` and `scripts/package`
/// both run.
public enum CCCURL: Equatable, Sendable {
    case attach(SessionRef)

    public static let scheme = "ccc"

    /// Why a URL is not one of ours, in words the notice can show.
    public struct Refusal: Error, Equatable, CustomStringConvertible {
        public var description: String
    }

    public static func parse(_ url: URL) throws -> CCCURL {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == scheme else {
            throw Refusal(description: "'\(url.absoluteString)' is not a ccc:// link")
        }
        let action = parts.host?.lowercased() ?? ""
        let path = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true)
        switch action {
        case "attach":
            guard path.count == 1, let text = String(path[0]).removingPercentEncoding,
                  let ref = SessionRef.parse(text) else {
                throw Refusal(description: "'\(url.absoluteString)' names no session (ccc://attach/<id, name, or host:id>)")
            }
            return .attach(ref)
        default:
            throw Refusal(description: "ccc does not know '\(action)' in \(url.absoluteString) (it knows ccc://attach/<ref>)")
        }
    }

    /// The link for a ref, percent-encoded: the inverse of `parse`, so the
    /// grammar has one writer as well as one reader.
    public var url: URL {
        switch self {
        case .attach(let ref):
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove("/")
            let path = ref.description.addingPercentEncoding(withAllowedCharacters: allowed) ?? ref.description
            return URL(string: "\(Self.scheme)://attach/\(path)")!
        }
    }
}
