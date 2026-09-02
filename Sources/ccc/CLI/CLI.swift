import CCCKit
import Foundation

/// The command face. Each verb is a click's twin.
///
///   ccc list [--json]                 the roster, with the model column
///   ccc attach <id> [--headless]      attach; headless drives a PTY and serves the socket
///   ccc snapshot [--json]             the pane's grid as text
///   ccc send <text> | --key <name>…   type into the pane
///   ccc detach                        detach the pane
///   ccc stats [--json]                memory, poll latency, PTY throughput
enum CLI {
    static func run(_ arguments: [String]) -> Int32 {
        var args = arguments
        let json = args.contains("--json")
        args.removeAll { $0 == "--json" }
        guard let verb = args.first else { return usage() }
        _ = json
        switch verb {
        case "help", "--help", "-h":
            return usage(to: .standardOutput, status: 0)
        default:
            FileHandle.standardError.write(Data("ccc: unknown command '\(verb)'\n".utf8))
            return usage()
        }
    }

    @discardableResult
    static func usage(to handle: FileHandle = .standardError, status: Int32 = 2) -> Int32 {
        handle.write(Data("""
        usage: ccc                              open the app
               ccc list [--json]
               ccc attach <id> [--headless]
               ccc snapshot [--json]
               ccc send <text> | --key <name>...
               ccc detach
               ccc stats [--json]

        """.utf8))
        return status
    }
}
